# encoding: UTF-8

require 'strscan'
require 'pathname'

module Distillery
class DatFile

#
# Parser for ClrMamePro DAT file
#
class ClrMamePro

    # Parse a DAT file in ClrMamePro format
    #
    # @param data [String]		data
    # 
    # @returns [Array<Object]		parsed file
    # @returns [nil]                    was not a ClrMamePro DAT file
    #
    # @raise [ContentError]		incorrect content
    #
    # Array returned: [ meta, <Array: game>, <Array: resources> ]
    #
    #  meta     = { 'name'         => < String             >,
    #               'description'  => < String             >,
    #               'category'     => < String             >,
    #               'version'      => < String             >,
    #               'author'       => < String             >,
    #               'forcemerging' => < 'none' | 'split' | 'full' >,
    #               'forcezipping' => < 'yes' | 'no'       >,
    #             }
    #
    #  rom      = { 'name'         => < String             >,
    #               'merge'        => < String             >,
    #               'size'         => < Integer            >,
    #               'flags'        => < String             >,
    #               'crc'          => < String: /^\h{8}$/  >,
    #               'md5           => < String: /^\h{32}$/ >,
    #               'sha1'         => < String: /^\h{40}$/ >,
    #             }
    #
    #  disk     = { 'name'         => < String             >,
    #               'merge'        => < String             >,
    #               'size'         => < Integer            >,
    #               'flags'        => < String             >,
    #               'crc'          => < String: /^\h{8}$/  >,
    #               'md5           => < String: /^\h{32}$/ >,
    #               'sha1'         => < String: /^\h{40}$/ >,
    #             }
    #
    #  resource = { 'name'         => < String             >,
    #               'merge'        => < String             >,
    #               'size'         => < Integer            >,
    #               'flags'        => < String             >,
    #               'crc'          => < String: /^\h{8}$/  >,
    #               'md5           => < String: /^\h{32}$/ >,
    #               'sha1'         => < String: /^\h{40}$/ >,
    #             }
    #
    #  game     = { 'name'         => < String             >,
    #               'romof'        => < String             >,
    #               'cloneof'      => < String             >,
    #               'description'  => < String             >,
    #               'year'         => < Integer            >,
    #               'rom'          => < Array: rom         >,
    #               'disk'         => < Array: disk        >,
    #               'sampleof'     => < String             >,
    #               'sample'       => < Array : String     >,
    #             }
    #
    #  resource = { 'name'         => < String             >,
    #               'description'  => < String             >,
    #               'year'         => < Integer            >,
    #               'rom'          => < Array: rom         >,
    #             }
    #
    def self.parse(data)
        self.new(data).send(:parse)
    end


    # Get a DatFile
    #
    # @param data [String]		data
    # 
    # @returns [DatFile]		DatFile object
    # @returns [nil]                    was not a ClrMamePro DAT
    #
    # @raise [ContentError]		incorrect content
    # 
    def self.get(data)
        # Parse ClrMamePro DAT file
        meta, games, resources = self.parse(data)

        # That's not a ClrMAmepro DAT file
        return nil if meta.nil?
        
        # Everything is considered as game (games, resources)
        games = (games + resources).map { |game|
            # Game name
            name = game.dig('name')
            # Everything is considered as a ROM (roms, disks, samples)
            roms = [ 'rom', 'disk', 'sample' ]
                .flat_map { |elt| game.dig(elt) }.compact.map { |rom|
                ROM::new(ROM::Path::Virtual.new(rom.dig('name')),
                         :size  => rom.dig('size'),
                         :crc32 => rom.dig('crc' ),
                         :md5   => rom.dig('md5' ),
                         :sha1  => rom.dig('sha1'))
            }
            # Build games
            Game::new(name, *roms, cloneof: game.dig('cloneof'))
        }

        # Metadata information
        meta = { :name        => meta.dig('name'       ),
                 :description => meta.dig('description'),
                 :version     => meta.dig('version'    ),
                 :author      => meta.dig('author'     ),
               }.compact

        # Returns datfile
        DatFile.new(games, **meta)
    end
    
    private
    

    def initialize(data)
        @data = data
    end

    # Parse data 
    def parse
        @s   = StringScanner.new(@data)
        @ok  = false
        
        meta, games, resources = {}, [], []
        while !@s.eos?
            case token = get_token
            when 'clrmamepro'		# clrmamepro ( ... )
                @ok = true
                get_token('(')
                meta = parse_clrmamepro
                get_token(')')
            when 'game'            	# game ( ... )
                get_token('(')
                games << parse_game
                get_token(')')
            when 'resource'             # resource ( ... )
                get_token('(')
                resources << parse_resource
                get_token(')')
            else
                unexpected!(token: token)
            end
        end

        [ meta, games, resources ]
    rescue ContentError => e
        @ok ? raise : false
    end

    # Push the current token back
    def unget_token
        @s.unscan
    end

    # Get the next token
    #
    # @param expected [Object]		allow token value checking/casting
    #                                   supported Integer, Pathname, #===
    #
    # @return [Object]
    #
    def get_token(expected = nil)
        # Skip white space
        @s.skip /\s+/
        # Fetch next token
        token = @s.scan /\b[^\s]+\b|\(|\)/
        if token.nil? && (token = @s.scan /"(?:[^"]|\\")*"/)
            token = token[1..-2].gsub('\\"', '"')
        end
        # Unexpected char?
        unexpected!(char: @s.peek(1)) if token.nil?     
        # Shortcut due to no extra checking
        return token                  if expected.nil?

        # Verify and convert to the expected token
        if    expected == Integer
            begin
                token = Integer(token)
            rescue ArgumentError
                expected!(token: expected)
            end
        elsif expected == Pathname
            token = File.join(token.split('\\'))
        else
            expected!(token: expected) unless expected === token
        end

        token
    end
        
    # Helper for raising unexpected exception
    #
    # @param h [Hash{Symbol => Object}]		one-item description
    #
    # @raise [ContentError]	parsing error
    #
    def unexpected!(h)
        raise ArgumentError if h&.size > 1
        if h.nil? || h.empty?
            raise ContentError, "unexpected parsing state"
        else
            k, v = h.first
            raise ContentError, "unexpected #{k}: '#{v}'"
        end
    end


    # Helper for raising expected exception
    #
    # @param h [Hash{Symbol => Object}]		one-item description
    #
    # @raise [ContentError]	parsing error
    #
    def expected!(h)
        raise ArgumentError if h&.size != 1
        k, v = h.first
        raise ContentError, "expected #{k}: '#{v}'"
    end
    
    # Parse group 'clrmamepro'
    def parse_clrmamepro
        {}.tap { |o|
            loop {
                case k = get_token
                when 'name'         then o[k] = get_token(String)
                when 'description'  then o[k] = get_token(String)
                when 'category'     then o[k] = get_token(String)
                when 'version'      then o[k] = get_token(String)
                when 'author'       then o[k] = get_token(String)
                when 'forcemerging' then o[k] = get_token(['none','split','full'])
                when 'forcezipping' then o[k] = get_token(['yes','no'])
                when ')'            then unget_token ; break
                else unexpected!(token: k)
                end
            }
        }
    end

    # Parse group 'game'
    def parse_game
        {}.tap { |o|
            loop {
                case k = get_token
                when 'name'         then o[k] = get_token(String)
                when 'romof'        then o[k] = get_token(String)
                when 'cloneof'      then o[k] = get_token(String)
                when 'description'  then o[k] = get_token(String)
                when 'year'         then o[k] = get_token(Integer)
                when 'manufacturer' then o[k] = get_token(String)
                when 'rom'
                    get_token('(')
                    (o[k] ||= []) << parse_rom
                    get_token(')')
                when 'disk'
                    get_token('(')
                    (o[k] ||= []) << parse_disk
                    get_token(')')
                when 'sampleof'     then o[k] = get_token(String)
                when 'sample'       then (o[k] ||= []) << get_token(String)
                when ')'            then unget_token ; break
                else unexpected!(token: k)
                end
            }
        }
    end

    # Parse group 'resource'
    def parse_resource
        {}.tap { |o|
            loop {
                case k = get_token
                when 'name'         then o[k] = get_token(Pathname)
                when 'description'  then o[k] = get_token(String)
                when 'year'         then o[k] = get_token(Integer)
                when 'rom'          then
                    get_token('(')
                    (o[k] ||= []) << parse_rom
                    get_token(')')
                when ')'            then unget_token ; break
                else unexpected!(token: k)
                end
            }
        }
    end

    # Parse group 'rom'
    def parse_rom
        {}.tap { |o|
            loop {
                case k = get_token
                when 'name'   then o[k] = get_token(Pathname)
                when 'merge'  then o[k] = get_token(String)
                when 'size'   then o[k] = get_token(Integer)
                when 'flags'  then o[k] = get_token(String)
                when 'crc'    then o[k] = get_token(/^\h{8}$/)
                when 'md5'    then o[k] = get_token(/^\h{32}$/)
                when 'sha1'   then o[k] = get_token(/^\h{40}$/)
                when ')'      then unget_token ; break
                else unexpected!(token: k)
                end
            }
        }
    end        
    
    # Parse group 'disk'
    def parse_disk
        {}.tap { |o|
            loop {
                case k = get_token
                when 'name'   then o[k] = get_token(Pathname)
                when 'merge'  then o[k] = get_token(String)
                when 'size'   then o[k] = get_token(Integer)
                when 'flags'  then o[k] = get_token(String)
                when 'crc'    then o[k] = get_token(/^\h{8}$/)
                when 'md5'    then o[k] = get_token(/^\h{32}$/)
                when 'sha1'   then o[k] = get_token(/^\h{40}$/)
                when ')'      then unget_token ; break
                else unexpected!(token: k)
                end
            }
        }
    end        

end

end
end

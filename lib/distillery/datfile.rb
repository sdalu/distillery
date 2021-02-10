# SPDX-License-Identifier: EUPL-1.2

require 'set'

require_relative 'error'
require_relative 'game'
require_relative 'rom'
require_relative 'vault'

require_relative 'datfile-clrmamepro'
require_relative 'datfile-logiqx'

module Distillery

# Handle information from DAT file
class DatFile
    class ContentError < Error
    end

    # List of ROM with loosely defined (ie: with some missing checksum)
    #
    # @return [Array<ROM>,nil]
    #
    def with_partial_checksum
        @roms.with_partial_checksum
    end


    # Get Games to which this ROM belongs.
    # @note This only works for ROMs created by the DatFile
    #
    # @param rom [Rom]
    #
    # @return [Array<Game>]
    #
    def getGames(rom)
        @roms_game[rom.object_id]
    end

    
    # Get DatFile representation from file.
    #
    # @param datfile [String]
    #
    # @returns [DatFile]
    #
    # @raises [ContentError]
    #
    def self.from_file(datfile)
        if !FileTest.file?(datfile)
            raise ArgumentError, "DAT file is missing or not a regular file"
        end
        
        data  = File.read(datfile, encoding: 'BINARY')
        
        dat ||= Logiqx.get(data)     if defined?(Logiqx)
        dat ||= ClrMamePro.get(data) if defined?(ClrMamePro)

        dat || raise(ContentError)
    end
    
    
    # Create DatFile representation
    #
    # @param games        [Array<Game>]		list of games
    # @param name	  [String]
    # @param description  [String]
    # @param url	  [String]
    # @param date	  [String]
    # @param version	  [String]
    # @param author	  [String]
    #
    def initialize(games, name: nil, description: nil, url: nil, date: nil, version: nil, author: nil)
        @games       = Set.new
        @roms        = Vault::new
        @roms_game   = {}

        @name        = name
        @description = description
        @url         = url
        @date        = date
        @version     = version
        @author      = author
        
        games.each do |game|
            game.roms.each do |rom|
                (@roms_game[rom.object_id] ||= []) << game
                @roms << rom
            end

            if @games.add?(game).nil?
                raise ContentError,
                      "Game '#{game}' defined multiple times in DAT file"
            end
        end

        @names  = @roms.each.group_by {|rom| rom.name }
                       .transform_values {|list| list.uniq {|a,b| a.same?(b) } }
    end


    # Lookup ROM by name
    #
    # @param name [String]		ROM name to lookup
    #
    # @return [Array<ROM>]
    # @return nil if not found
    #
    def lookup(name)
        @names[name]
    end
    
    
    # Identify ROM which have the same path/name but are different
    #
    # @param type [:path, :name]	Check by path or name
    #
    # @return [Hash{String => Array<ROM>}]
    #
    def clash(type = :path)
        grp = case type
              when :path then @roms.each.group_by(&:path)
              when :name then @roms.each.group_by(&:name)
              else raise ArgumentError
              end

        grp.select           { |_, roms| roms.size > 1 }
           .transform_values { |roms|
            lst = []
            while rom = roms.first do
                t, f = roms.partition { |r| r.same?(rom) }
                lst << t.first
                roms = f
            end
            lst
        }
    end


    # @return [Vault]
    attr_reader :roms


    # Iterate over each ROM
    #
    # @yieldparam rom [ROM]
    #
    # @return [self,Enumerator]
    #
    def each_rom
        block_given? ? @roms.each { |rom| yield(rom) }
                     : @roms.each
    end


    # @return [Set<Games>]
    attr_reader :games


    # Iterate over each game
    #
    # @yieldparam game [Game]
    #
    # @return [self,Enumerator]
    #
    def each_game
        block_given? ? @games.each { |game| yield(game) }
                     : @games.each
    end


    # Datfile name
    #
    # @return [String,nil]
    attr_reader :name


    # Datfile description
    #
    # @return [String,nil]
    attr_reader :description


    # Datfile url
    #
    # @return [String,nil]
    attr_reader :url


    # Datfile date
    #
    # @return [String,nil]
    attr_reader :date


    # Datfile version
    #
    # @return [String,nil]
    attr_reader :version

    # Datfile author
    #
    # @return [String,nil]
    attr_reader :author

end

end

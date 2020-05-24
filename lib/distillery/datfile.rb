# SPDX-License-Identifier: EUPL-1.2

require 'set'
require 'nokogiri'

require_relative 'error'
require_relative 'game'
require_relative 'rom'
require_relative 'vault'

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


    # Create DatFile representation from file.
    #
    # @param datfile [String]
    #
    def initialize(datfile)
        @games     = Set.new
        @roms      = Vault::new
        @roms_game = {}

        if !FileTest.file?(datfile)
            raise ArgumentError, "DAT file is missing or not a regular file"
        end

        # Get datafile as XML document
        dat = Nokogiri::XML(File.read(datfile))

        dat.xpath('//header').each do |hdr|
            @name        = hdr.xpath('name'       )&.first&.content
            @description = hdr.xpath('description')&.first&.content
            @url         = hdr.xpath('url'        )&.first&.content
            @date        = hdr.xpath('date'       )&.first&.content
            @version     = hdr.xpath('version'    )&.first&.content
        end

        # Process each game elements
        dat.xpath('//game').each do |g|
            releases = g.xpath('release').map { |r|
                Release::new(r[:name], region: r[:region].upcase)
            }
            roms     = g.xpath('rom').map { |r|
                path = File.join(r[:name].split('\\'))
                ROM::new(ROM::Path::Virtual.new(path),
                         :size  => Integer(r[:size]),
                         :crc32 => r[:crc ],
                         :md5   => r[:md5 ],
                         :sha1  => r[:sha1])
            }
            game     = Game::new(g['name'], *roms, releases: releases,
                                                    cloneof: g['cloneof'])

            roms.each do |rom|
                (@roms_game[rom.object_id] ||= []) << game
                @roms << rom
            end

            if @games.add?(game).nil?
                raise ContentError,
                      "Game '#{game}' defined multiple times in DAT file"
            end
        end
    end

    # Identify ROM which have the same fullname/name but are different
    #
    # @param type [:fullname, :name]	Check by fullname or name
    #
    # @return [Hash{String => Array<ROM>}]
    #
    def clash(type = :fullname)
        grp = case type
              when :fullname then @roms.each.group_by {|rom| rom.fullname      }
              when :name     then @roms.each.group_by {|rom| rom.name          }
              else raise ArgumentError
              end

        grp.select           {|_, roms| roms.size > 1 }
           .transform_values {|roms|
            lst = []
            while rom = roms.first do
                t, f = roms.partition {|r| r.same?(rom) }
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
        block_given? ? @roms.each {|r| yield(r) }
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
        block_given? ? @games.each {|g| yield(g) }
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
    
end

end

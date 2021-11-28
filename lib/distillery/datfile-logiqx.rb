# encoding: UTF-8

require 'nokogiri'

module Distillery
class DatFile

#
# Parser for XML Logiqx DAT file
#
class Logiqx

    # Parse a DAT file in ClrMamePro format
    #
    # @param data [String]		data
    # 
    # @returns [Array<Object]		parsed file
    # @returns [nil]                    was not a Logiqx DAT file
    #
    # @raise [ContentError]		incorrect content
    #
    # Array returned: [ meta, <Array: game>, <Array: resources> ]
    #
    #  meta     = { 'name'         => < String             >,
    #               'description'  => < String             >,
    #               'version'      => < String             >,
    #               'date'         => < String             >,
    #               'author'       => < String             >,
    #               'url'          => < String             >,
    #             }
    #
    #  release  = { 'name'         => < String             >,
    #               'region'       => < String             >,
    #             }
    #
    #  rom      = { 'name'         => < String             >,
    #               'size'         => < Integer            >,
    #               'crc'          => < String: /^\h{8}$/  >,
    #               'md5           => < String: /^\h{32}$/ >,
    #               'sha1'         => < String: /^\h{40}$/ >,
    #             }
    #
    #  game     = { 'name'         => < String             >,
    #               'release'      => < Array: release     >,
    #               'cloneof'      => < String             >,
    #               'rom'          => < Array: rom         >,
    #             }
    #
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
        # Parse Logiqx DAT file
        meta, games = self.parse(data)

        # That's not a Logiqx DAT file
        return nil if meta.nil?

        # Everything is considered as game (games, resources)
        games.map! { |game|
            # Game name
            name = game.dig('name')
            # Everything is considered as a ROM (roms, disks, samples)
            roms = game.dig('rom').map { |rom|
                ROM::new(ROM::Path::Virtual.new(rom.dig('name')),
                         :size  => rom.dig('size'),
                         :crc32 => rom.dig('crc' ),
                         :md5   => rom.dig('md5' ),
                         :sha1  => rom.dig('sha1'))
            }
            # Build games
            Game::new(name, *roms, cloneof: game.dig('cloneof'))
        }

        # Returns datfile
        DatFile.new(games, **meta)
    end


    def self.get_meta(data)
        # Parse Logiqx DAT file
        meta, games = self.parse(data)

        # That's not a Logiqx DAT file
        return nil if meta.nil?

        meta
    end
    
    private
    

    def initialize(data)
        @data = data
    end

    # Parse data 
    def parse
        # Get datafile as XML document
        dat = Nokogiri::XML(@data) { |config| config.strict.nonet }

        # Check for a Logiqx DTD
        unless dat.internal_subset&.external_id ==
               "-//Logiqx//DTD ROM Management Datafile//EN"
            return nil
        end

        # Process meta data
        meta = {}
        dat.xpath('//header').each do |hdr|
            meta[:name       ] = hdr.xpath('name'       )&.first&.content
            meta[:description] = hdr.xpath('description')&.first&.content
            meta[:version    ] = hdr.xpath('version'    )&.first&.content
            meta[:date       ] = hdr.xpath('date'       )&.first&.content
            meta[:author     ] = hdr.xpath('author'     )&.first&.content
            meta[:url        ] = hdr.xpath('url'        )&.first&.content
        end

        # Process each game elements
        games = dat.xpath('//game').map { |g|
            releases = g.xpath('release').map { |r|
                Release::new(r[:name], region: r[:region].upcase)
            }
            roms     = g.xpath('rom').map { |r|
                { 'name' => File.join(r[:name].split('\\')),
                  'size' => Integer(r[:size]),
                  'crc'  => r[:crc ],
                  'md5'  => r[:md5 ],
                  'sha1' => r[:sha1],
                }.compact
            }

            { 'name'    => g['name'],
              'rom'     => roms,
              'release' => releases,
              'cloneof' => g['cloneof'],
            }.compact                
        }
        
        [ meta, games ]
    rescue Nokogiri::XML::SyntaxError        
        nil # Doesn't look like an XML file
    end

end

end
end

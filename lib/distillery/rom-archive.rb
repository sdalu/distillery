# SPDX-License-Identifier: EUPL-1.2

require 'set'

require_relative 'archiver'
require_relative 'archiver/external'
require_relative 'archiver/zip'
require_relative 'rom'
require_relative 'rom/path'
require_relative 'rom/path/archive'

#require 'logger'
#Distillery::Archiver.logger = Logger.new($stderr)
Distillery::Archiver.registering



module Distillery

# Deal with ROM embedded in an archive file.
#
class ROMArchive
    include Enumerable

    # Prefered
    PREFERED   = '7z'.freeze

    # Allowed extension names
    EXTENSIONS = Set[ '7z', 'zip' ].freeze


    # @!visibility private
    EXTENSIONS_REGEXP = /(?: #{ EXTENSIONS.map { |ext| Regexp.escape(ext) }
                                          .join('|') } 
                         )/x.freeze
    FILE_REGEXP       = /(?<file>.+\.#{EXTENSIONS_REGEXP})/x.freeze
    ENTRY_REGEXP      = /(?<entry>.+)/.freeze


    # Parse an archive path, and return it's file and entry
    #
    # @param str        [String]	string to parse
    # @param separator  [String]        separator to use
    #                                   default to ROM::Path::Archive.separator
    #
    # @return [Array<String>] file and entry
    #
    def self.parse_path(str, separator = nil)
        separator ||= ROM::Path::Archive.separator
        sepsize     = separator.size
        regexp      = case sepsize
                      when 2
                          sb = Regexp.escape(separator[0])
                          se = Regexp.escape(separator[1])
                          /\A#{FILE_REGEXP}#{sb}#{ENTRY_REGEXP}#{se}\Z/
                      when 1
                          s  = Regexp.escape(separator)
                          /\A#{FILE_REGEXP}#{s}#{ENTRY_REGEXP}\Z/
                      else
                          raise ArgumentError
                      end
        
        if m = str.match(regexp)
            [ m[:file], m[:entry] ]
        end
    end


    # Set buffer size used when processing archive content
    #
    # @param size [Integer]             size in kbytes
    #
    def self.bufsize=(size)
        @@bufsize = size << 10
    end


    # Check using extension if file is an archive
    #
    # @param file [String]              file to test
    #
    # @return [Boolean]
    #
    def self.archive?(file, archives: EXTENSIONS)
        return false if archives.nil?

        archives.include?(File.extname(file)[1..-1])
    end


    # Read ROM archive from file
    #
    # @param file [String]              path to archive file
    # @param headers [Array,nil,false]  header definition list
    #
    # @yieldparam entry			entry being processed
    # @yieldreturn [Boolean]		should the entry be added
    #
    # @return [ROMArchive]
    #
    def self.from_file(file, headers: nil)
        # Create archive object
        archive = self.new(file)

        # Iterate on archive entries
        Distillery::Archiver.for(file).each do |entry, i|
            next if block_given? && !yield(entry)
            path = ROM::Path::Archive.new(archive, entry)
            archive[entry] = ROM.new(path, **ROM.info(i, headers: headers))
        end

        archive
    end


    # Create an empty archive
    #
    # @param file [String]              archive file
    #
    def initialize(file)
        dirname, basename = File.split(file)
        @file   = dirname == '.' ? basename : file
        @roms   = {}
    end


    # String representation of the archive
    # @return [String]
    def to_s
        @file
    end


    # Assign a ROM to the archive
    #
    # @param entry [String]             archive entry name
    # @param rom   [ROM]                ROM
    #
    # @return [ROM]                     the assigned ROM
    #
    def []=(entry, rom)
        @roms.merge!(entry => rom) { |key, _old_rom, new_rom|
            warn "replacing ROM entry \"#{key}\" (#{self})"
            new_rom
        }
        rom
    end


    # Same archive file
    #
    # @param o [ROMArchive]             other archive
    # @return [Boolean]
    #
    def same_file?(o)
        self.file == o.file
    end


    # Test if archive is identical (same file, same content)
    #
    # @param o [ROMArchive]             other archive
    # @return [Boolean]
    #
    def ==(o)
        o.is_a?(ROMArchive)                                        &&
        (self.entries.to_set == o.entries.to_set)                  &&
        self.entries.all? { |entry| self[entry].same?(o[entry]) }
    end


    # Archive size (number of entries)
    # @return [Integer]
    def size
        @roms.size
    end


    # Iterate over each ROM
    #
    # @yieldparam rom [ROM]
    #
    # @return [self,Enumerator]
    #
    def each
        block_given? ? @roms.each_value { |r| yield(r) }
                     : @roms.each_value
    end


    # List of ROMs
    #
    # @return [Array<ROM>]
    #
    def roms
        @roms.values
    end


    # List of archive entries
    #
    # @return [Array<String>]
    #
    def entries
        @roms.keys
    end


    # Get ROM by entry
    #
    # @param entry [String]             archive entry
    # @return [ROM]
    #
    def [](entry)
        @roms[entry]
    end


    # Delete entry
    #
    # @param entry [String]             archive entry
    #
    # @return [Boolean]                 operation status
    #
    def delete!(entry)
        Distillery::Archiver.for(@file) do |archive|
            archive.delete!(entry).tap do |deleted|
                File.unlink(@file) if deleted && archive.empty?
            rescue Errno::ENOENT
            end
        end
    end


    # Read ROM.
    # @note Can be costly, to be avoided.
    #
    # @param entry [String]             archive entry
    #
    # @yieldparam [#read] io            stream for reading
    #
    # @return block value
    #
    def reader(entry, &block)
        Distillery::Archiver.for(@file).reader(entry, &block)
    end


    # Extract rom to the filesystem
    #
    # @param entry  [String]            entry (rom) to extract
    # @param to     [String]            destination
    # @param length [Integer,nil]       data length to be copied
    # @param offset [Integer]           data offset
    # @param force  [Boolean]           remove previous file if necessary
    #
    # @return [Boolean]                 operation status
    #
    def extract(entry, to, length = nil, offset = 0, force: false)
        Distillery::Archiver.for(@file).reader(entry) do |i|
            # Copy file
            begin
                op = force ? File::TRUNC : File::EXCL
                File.open(to, File::CREAT | File::WRONLY | op) do |o|
                    while (skip = [ offset, @@bufsize ].min) > 0
                        break if i.read(skip).nil? # skip and check for EOF
                        offset -= skip
                    end

                    if length.nil?
                        while data = i.read(@@bufsize)
                            o.write(data)
                        end
                    else
                        while ((sz = [ length, @@bufsize ].min) > 0) &&
                              (data = i.read(sz))
                            o.write(data)
                            length -= sz
                        end
                    end
                end
            rescue Errno::EEXIST
                return false
            end

            # Assuming entries are unique
            return true
        end

        # Was not found
        false
    end


    # Archive file
    # @return [String]
    attr_reader :file
end


# Set default buffer size to 32k
ROMArchive.bufsize = 32

end

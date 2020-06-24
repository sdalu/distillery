# SPDX-License-Identifier: EUPL-1.2

require 'zlib'
require 'set'
require 'fileutils'

require_relative '../path'
require_relative 'file'

module Distillery
class ROM
class Path

# Path from a file
class FileCompressed < File
    # @!visibility private
    SEEK_BUFSIZE = 16 * 1024
    
    # Supported compression (by prefix)
    SUPPORTED = Set[ 'gz' ].freeze
    
    # Returns a new instance of File.
    #
    # @param entry     [String]           path to file in basedir
    # @param extension [String]           file extension
    # @param basedir   [String, nil]      base directory
    #
    def initialize(entry, extension, basedir)
        # Sanity check
        if ! SUPPORTED.include?(extension)
            raise ArgumentError,
                  "compression extension not supported (#{extension})"
        end

        # Call parent
        super(entry, basedir)

        # Save context
        @extension = extension
    end


    # (see ROM::Path#file)
    def file
        super + '.' + @extension
    end


    # (see ROM::Path#reader)
    def reader(&block)
        Zlib::GzipReader.open(self.file, &block)
    end


    # (see ROM#copy)
    def copy(to, length = nil, offset = 0, force: false, link: :hard)
        # Avoid copy if destination exist and is identical
        if (!force && length.nil? && offset.zero? &&
            ::File.exist?(to) && self.same?(ROM.from_file(to)))
            return true
        end

        # Ensure sub-directories are created
        FileUtils.mkpath(::File.dirname(to))

        # Copy file
        op = force ? ::File::TRUNC : ::File::EXCL
        ::File.open(file, ::File::RDONLY) do |i|
            # Apply stream decompressor
            i = Zlib::GzipReader.new(i)

            # Seek to offset position
            # (use our implementation if not available)
            if i.respond_to?(:seek)
                i.seek(offset)
            else
                while (skip = [ offset, SEEK_BUFSIZE ].min ) > 0
                    break if i.read(skip).nil? # skip and check for EOF
                    offset -= skip
                end
            end

            # Perform stream copy
            ::File.open(to, ::File::CREAT | ::File::WRONLY | op) do |o|
                IO.copy_stream(i, o, length)
            end
        end
    end


    # (see ROM#rename)
    def rename(path, force: false)
        unless path.instance_of?(String) && path.end_with?(".#{@extension}")
            raise ArgumentError, 'only supporting same compression renaming'
        end
        super(path, force: force)
    end

end

end
end
end

# SPDX-License-Identifier: EUPL-1.2

require 'zlib'
require 'set'
require 'fileutils'

require_relative '../path'

module Distillery
class ROM
class Path

# Path from a file
class FileCompressed < Path
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

        if entry.start_with?('/')
            raise ArgumentError, "entry must be relative to basedir"
        end

        # Save context
        @entry     = entry
        @basedir   = basedir || '.'
        @extension = extension
    end


    # (see ROM::Path#to_s)
    def to_s
        self.file
    end


    # (see ROM::Path#file)
    def file
        if @basedir == '.'
        then @entry + '.' + @extension
        else ::File.join(@basedir, @entry) + '.' + @extension
        end
    end


    # (see ROM::Path#storage)
    def storage
        @basedir
    end


    # (see ROM::Path#entry)
    def entry
        @entry
    end


    # (see ROM::Path#basename)
    def basename
        ::File.basename(@entry)
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
            i = Zlib::GzipReader.new(i)
            if i.respond_to?(:seek)
                i.seek(offset)
            else
                while (skip = [ offset, SEEK_BUFSIZE ].min ) > 0
                    break if i.read(skip).nil? # skip and check for EOF
                    offset -= skip
                end
            end

            ::File.open(to, ::File::CREAT | ::File::WRONLY | op) do |o|
                IO.copy_stream(i, o, length)
            end
        end
    end


    # (see ROM#rename)
    def rename(path, force: false)
        case path
        when String
        else raise ArgumentError, "unsupported path type (#{path.class})"
        end

        file = if path.start_with?('/')
               then path
               else ::File.join(@basedir, path)
               end

        if !::File.exist?(file)
            ::File.rename(self.file, file) == 0
        elsif self.same?(ROM.from_file(file))
            ::File.unlink(self.file) == 1
        elsif force
            ::File.rename(self.file, file) == 0
        else
            false
        end
    rescue SystemCallError
        false
    end


    # (see ROM#delete!)
    def delete!
        ::File.unlink(self.file) == 1
    rescue SystemCallError
        false
    end
end

end
end
end

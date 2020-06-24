# SPDX-License-Identifier: EUPL-1.2

require_relative '../path'

module Distillery
class ROM
class Path

# Path from a file
class File < Path
    # Returns a new instance of File.
    #
    # @param entry   [String]           path to file in basedir
    # @param basedir [String, nil]      base directory
    #
    def initialize(entry, basedir = nil)
        # Sanity check
        if entry.start_with?('/')
            raise ArgumentError, "entry must be relative to basedir"
        end

        # Save context
        @entry   = entry
        @basedir = basedir || '.'
    end


    # (see ROM::Path#to_s)
    def to_s
        self.file
    end


    # (see ROM::Path#file)
    def file
        if @basedir == '.'
        then @entry
        else ::File.join(@basedir, @entry)
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
        ::File.open(self.file, ::File::RDONLY, binmode: true, &block)
    end


    # (see ROM#copy)
    def copy(to, length = nil, offset = 0, force: false, link: :hard)
        (!force && length.nil? && offset.zero? &&
         ::File.exist?(to) && self.same?(ROM.from_file(to))) ||
            ROM.filecopy(self.file, to, length, offset,
                         force: force, link: link)
    end


    # (see ROM#rename)
    def rename(path, force: false)
        case path
        when String
        else raise ArgumentError, "unsupport path type (#{path.class})"
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

# SPDX-License-Identifier: EUPL-1.2

require_relative '../path'

module Distillery
class ROM
class Path

# Path from archive, binding archive and entry together.
class Archive < Path

    # @!visibility private
    @@separator = '#'


    # Set the separator used to distinguish archive file from entry
    #
    # @param sep        [String]        separator
    #
    def self.separator=(sep)
        @@separator = sep.dup.freeze
    end


    # Get the separator used to distinguish archive file from entry
    #
    # @return [String,Array]
    #
    def self.separator
        @@separator
    end


    # Create a an Archive Path instance
    #
    # @param archive [ROMArchive]       archive instance
    # @param entry   [String]           archive entry
    #
    def initialize(archive, entry)
        @archive = archive
        @entry   = entry
    end


    # (see ROM::Path#to_s)
    def to_s(separator = nil)
        separator ||= @@separator
        "#{self.file}#{separator[0]}#{self.entry}#{separator[1]}"
    end


    # (see ROM::Path#file)
    def file
        @archive.file
    end


    # (see ROM::Path#storage)
    def storage
        self.file
    end


    # (see ROM::Path#entry)
    def entry
        @entry
    end


    # (see ROM::Path#basename)
    def basename
        ::File.basename(self.entry)
    end


    # (see ROM::Path#grouping)
    def grouping
        [ self.storage, self.entry, @archive.size ]
    end


    # (see ROM::Path#reader)
    def reader(&block)
        @archive.reader(@entry, &block)
    end


    # (see ROM::Path#copy)
    def copy(to, length = nil, offset = 0, force: false, link: :hard)
        # XXX: improve like String
        @archive.extract(@entry, to, length, offset, force: force)
    end


    # (see ROM::Path#rename)
    def rename(path, force: false)
        # XXX: improve like String
        @archive.rename(@entry, path, force: force)
    end


    # (see ROM::Path#delete!)
    def delete!
        @archive.delete!(@entry)
    end

    # Returns the value of attribute archive
    # @return [ROMArchive]
    attr_reader :archive

end

end
end
end

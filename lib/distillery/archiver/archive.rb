# SPDX-License-Identifier: EUPL-1.2

module Distillery
class Archiver

# Allow archive file processing
#
# All the operations are forwarded to an {Archiver} instance
# which is able to process the selected archive file.
#
class Archive
    include Enumerable

    # Returns a new instance of Archive.
    #
    # @param file [String]              file holding the archive
    # @param archiver [Archiver]	force use of the specified archiver
    #                                   otherwise infer it from the file name
    #
    # @raise [ArchiverNotFound]         an archiver able to process this file
    #                                   has not been found
    #
    def initialize(file, archiver = nil)
        @file     = file.dup.freeze
        @archiver = archiver || Archiver.for_file(file)

        if @archiver.nil?
            raise ArchiverNotFound, "no archiver available (#{file})"
        end
    end


    # Returns the file this archive instance is bound to
    #
    # @return [String]  path to archive
    #
    def file
        @file
    end

    
    # Iterate over each archive entry
    #
    # @yieldparam entry [String]        entry name
    # @yieldparam io    [InputStream]   input stream
    #
    # @return [self,Enumerator]
    #
    def each(&block)
        @archiver.each(@file, &block)
        self
    end


    # List of entries for the archive
    #
    # @return [Array<String>]
    #
    def entries
        @archiver.entries(@file)
    end


    # Does the archive exist?
    #
    # @return [Boolean]
    #
    def exist?
        @archiver.exist?(@file)
    end


    # Is the archive emtpy?
    #
    # @return [Boolean]
    #
    def empty?
        @archiver.empty?(@file)
    end


    # Check if the archive contains the specified entry
    #
    # @param entry [String]             entry name
    #
    # @return [Boolean]
    #
    def include?(entry)
        @archiver.include?(@file, entry)
    end


    # Allow to perform read operation on an archive entry
    #
    # @param entry [String]             entry name
    #
    # @yieldparam io [InputStream]      input stream for reading
    #
    # @return                           block value
    #
    def reader(entry, &block)
        @archiver.reader(@file, entry, &block)
    end


    # Allow to perform write operation on an archive entry
    #
    # @param entry [String]             entry name
    #
    # @yieldparam io [OutputStream]     output stream for writing
    #
    # @return                           block value
    #
    def writer(entry, &block)
        @archiver.writer(@file, entry, &block)
    end


    # Check if two entries are identical
    #
    # @param entry_1 [String]             entry 1
    # @param entry_2 [String]             entry 2
    #
    # @return [Boolean]
    #
    def same?(entry_1, entry_2)
        @archiver.same?(file, entry_1, entry_2)
    end

    
    # Delete the entry from the archive
    #
    # @param entry [String]             entry name
    #
    # @return [Boolean]         operation status
    #
    def delete!(entry)
        @archiver.delete!(@file, entry)
    end


    # Create a copy of the archive entry
    #
    # @param entry     [String]         entry name
    # @param new_entry [String]         new entry name
    # @param force     [Boolean]        remove previous entry if necessary
    #
    # @return [Boolean]         operation status
    #
    def copy(entry, new_entry, force: false)
        @archiver.copy(@file, entry, new_entry, force: force)
    end

    
    # Rename archive entry
    #
    # @param entry [String]             entry name
    # @param new_entry [String]         new entry name
    # @param force [Boolean]            remove previous entry if necessary
    #
    # @return [Boolean]         operation status
    #
    def rename(entry, new_entry, force: false)
        @archiver.rename(@file, entry, new_entry, force: force)
    end
end

end
end

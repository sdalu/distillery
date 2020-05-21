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
    # @param file [String]		file holding the archive
    #
    # @raise [ArchiverNotFound]		an archiver able to process this file
    #					has not been found
    #
    def initialize(file)
        @file     = file
        @archiver = Archiver.for_file(file)

        if @archiver.nil?
            raise ArchiverNotFound, "no archiver avalaible for this file"
        end
    end

    
    # Iterate over each archive entry
    #
    # @yieldparam entry [String]	entry name
    # @yieldparam io    [InputStream]	input stream
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


    # Is the archive emtpy?
    #
    # @return [Boolean]
    #
    def empty?
        @archiver.empty?(@file)
    end

    
    # Allow to perform read operation on an archive entry
    #
    # @param entry [String]		entry name
    #
    # @yieldparam io [InputStream]	input stream for reading
    #
    # @return 				block value
    #
    def reader(entry, &block)
        @archiver.reader(@file, entry, &block)
    end

    
    # Allow to perform write operation on an archive entry
    #
    # @param entry [String]		entry name
    #
    # @yieldparam io [OutputStream]	output stream for writing
    #
    # @return 				block value
    #
    def writer(entry, &block)
        @archiver.writer(@file, entry, &block)
    end

    
    # Delete the entry from the archive
    #
    # @param entry [String]		entry name
    #
    # @return [Boolean]		operation status
    #
    def delete!(entry)
        @archiver.delete!(@file, entry)
    end

    
end
    
end
end

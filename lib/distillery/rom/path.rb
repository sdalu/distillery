# SPDX-License-Identifier: EUPL-1.2

module Distillery
class ROM

# @abstract Abstract class used for ROM path    
class Path

    # Path value as string.
    #
    # @return [String]
    #
    def to_s
        raise NotImplementedError
    end

    # File directly accessible on the file system
    #
    # @return [String]
    #
    def file
        raise NotImplementedError
    end


    # File or directory that is considered the storage space for entries
    #
    # @return [String]
    #
    def storage
        raise NotImplementedError
    end


    # Entry
    #
    # @return [String]
    #
    def entry
        raise NotImplementedError
    end


    # Get path basename
    #
    # @return [String]
    #
    def basename
        raise NotImplementedError
    end

    
    # ROM reader
    # @note Can be costly, prefer existing #copy if possible
    #
    # @yieldparam [#read] io		stream for reading
    #
    # @return block value
    #
    def reader(&block)
        raise NotImplementedError
    end


    # Copy ROM content to the filesystem, possibly using link if requested.
    #
    # @param to    [String]		file destination
    # @param length [Integer,nil]	data length to be copied
    # @param offset [Integer]		data offset
    # @param force [Boolean]		remove previous file if necessary
    # @param link  [:hard, :sym, nil]	use link instead of copy if possible
    #
    # @return [Boolean]			status of the operation
    #
    def copy(to, length = nil, offset = 0, force: false, link: :hard)
        raise NotImplementedError
    end

    
    # Rename ROM and physical content.
    #
    # @note Renaming could lead to silent removing if same ROM is on its way
    #
    # @param path  [String]		new ROM path
    # @param force [Boolean]		remove previous file if necessary
    #
    # @return [Boolean]			status of the operation
    #
    def rename(path, force: false)
        raise NotImplementedError
    end


    # Delete physical content.
    #
    # @return [Boolean]
    #
    def delete!
        raise NotImplementedError
    end
end

end
end



require_relative 'path/virtual'
require_relative 'path/archive'
require_relative 'path/file'

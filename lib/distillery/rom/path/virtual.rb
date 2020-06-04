# SPDX-License-Identifier: EUPL-1.2

require_relative '../path'

module Distillery
class ROM
class Path

# Path without physical implementation.
# Used for ROM defined in DAT file
class Virtual < Path

    # @param entry [String]
    def initialize(entry)
        raise ArgumentError unless entry.is_a?(String)

        @entry = entry
    end


    # (see ROM::Path#to_s)
    def to_s
        @entry
    end


    # (see ROM::Path#file)
    def file
        nil
    end


    # (see ROM::Path#storage)
    def storage
        nil
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
    def reader
        nil
    end


    # (see ROM::Path#copy)
    def copy(to, length = nil, offset = 0, force: false, link: :hard)
        false
    end


    # (see ROM::Path#rename)
    def rename(path, force: false)
        case path
        when String then @entry = path
        else raise ArgumentError, "unsupport path type (#{path.class})"
        end
        true
    end


    # (see ROM::Path#delete!)
    def delete!
        true
    end
end

end
end
end

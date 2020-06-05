# SPDX-License-Identifier: EUPL-1.2

require 'digest'
require 'digest/sha1'
require 'zlib'
require 'fileutils'

require_relative 'error'
require_relative 'rom/path'
require_relative 'rom/path/file'
require_relative 'rom/path/virtual'

module Distillery

# ROM representation. It will typically have a name (entry) and hold
# information about it's content (size and checksums). If physical
# content is present it is referenced by it's path
#
class ROM
    class HeaderLookupError < Error
    end
        
    # @!visibility private
    HEADERS = [
        # Nintendo : Family Computer Disk System
        { :name   => 'Family Computer Disk System',
          :ext    => 'fds',
          :rules  => [ [ 0, 'FDS' ] ],
          :offset => 16,
        },
        # Nintendo : NES
        { :name   => 'NES',
          :ext    => 'nes',
          :rules  => [ [ 0, 'NES' ] ],
          :offset => 16,
        },
        # Atari    : Lynx
        { :name   => 'Atary Lynx',
          :ext    => 'lnx',
          :rules  => [ [ 0, 'LYNX' ] ],
          :offset => 64,
        },
        # Atari    : 7800
        # http://7800.8bitdev.org/index.php/A78_Header_Specification
        { :name   => 'Atari 7800',
          :ext    => 'a78',
          :rules  => [ [  1, 'ATARI7800' ],
                       [ 96, "\x00\x00\x00\x00ACTUAL CART DATA STARTS HERE" ] ],
          :offset => 128,
        },
    ]

    # @!visibility private
    CHECKSUMS_DEF    = {
        :sha256 => [ 256, 'e3b0c44298fc1c149afbf4c8996fb924'    \
                          '27ae41e4649b934ca495991b7852b855'         ],
        :sha1   => [ 160, 'da39a3ee5e6b4b0d3255bfef95601890afd80709' ],
        :md5    => [ 128, 'd41d8cd98f00b204e9800998ecf8427e'         ],
        :crc32  => [  32, '00000000'                                 ],
    }.freeze

    # List of supported weak checksums sorted by strength order
    # (a subset of {CHECKSUMS})
    CHECKSUMS_WEAK   = [ :crc32 ].freeze

    # List of supported strong checksums sorted by strength order
    # (a subset of {CHECKSUMS})

    CHECKSUMS_STRONG = [ :sha256, :sha1, :md5 ].freeze

    # List of all supported checksums sorted by strength order
    CHECKSUMS        = (CHECKSUMS_STRONG + CHECKSUMS_WEAK).freeze

    # List of all DAT supported checksums sorted by strengh order
    CHECKSUMS_DAT    = [ :sha1, :md5, :crc32 ].freeze

    # Checksum used when saving to file-system
    FS_CHECKSUM      = :sha1


    # Get information about ROM file (size, checksum, header, ...)
    #
    # @param io      [#read]            input object responding to read
    # @param bufsize [Integer]          buffer size in kB
    # @param headers [Array,nil,false]  header definition list
    #
    # @return [Hash{Symbol=>Object}]    ROM information
    #
    def self.info(io, bufsize: 32, headers: nil)
        # Sanity check
        raise ArgumentError, "bufsize argument must be > 0" if bufsize <= 0

        # Apply default
        headers ||= HEADERS

        # Adjust bufsize (from kB to B)
        bufsize <<= 10

        # Initialize info
        offset = 0
        size   = 0
        sha256 = Digest::SHA256.new
        sha1   = Digest::SHA1.new
        md5    = Digest::MD5.new
        crc32  = 0

        # Process whole data
        if x = io.read(bufsize)
            if headers != false
                begin
                    if offset = self.headered?(x, headers: headers)
                        x = x[offset..-1]
                    end
                rescue HeaderLookupError
                    # Sample is likely too short to perform header lookup
                    # => consider it not headered
                end
            end

            loop do
                size   += x.length
                sha256 << x
                sha1   << x
                md5    << x
                crc32   = Zlib::crc32(x, crc32)
                break unless x = io.read(bufsize)
            end
        end

        # Return info
        { :sha256 => sha256.digest,
          :sha1   => sha1.digest,
          :md5    => md5.digest,
          :crc32  => crc32,
          :size   => size,
          :offset => offset,
        }.compact
    end


    # Check if an header is detected
    #
    # @param data    [String]           data sample for header detection
    # @param ext     [String,nil]       extension name as hint
    # @param headers [Array]            header definition list
    #
    # @raise [HeaderLookupError]        sample is too short
    #
    # @return [Integer]                 Header size
    # @return [nil]                     No header found
    #
    def self.headered?(data, ext: nil, headers: HEADERS)
        # Normalize
        ext  = ext[1..-1] if ext && (ext[0] == '.')

        size = data.size
        hdr  = headers.find { |rules:, **|
            rules.all? { |offset, string|
                if (offset + string.size) > size
                    raise HeaderLookupError
                end
                data[offset, string.size] == string
            }
        }

        hdr&.[](:offset)
    end


    # Copy file, possibly using link if requested.
    #
    # @param from   [String]            file to copy
    # @param to     [String]            file destination
    # @param length [Integer,nil]       data length to be copied
    # @param offset [Integer]           data offset
    # @param force  [Boolean]           remove previous file if necessary
    # @param link   [:hard, :sym, nil]  use link instead of copy if possible
    #
    # @return [Boolean]                 status of the operation
    #
    def self.filecopy(from, to, length = nil, offset = 0,
                      force: false, link: :hard)
        # Ensure sub-directories are created
        FileUtils.mkpath(File.dirname(to))

        # If whole file is to be copied try optimisation
        if length.nil? && offset.zero?
            # If we are on the same filesystem, we can use hardlink
            f_stat = File.stat(from)
            f_dev  = [ f_stat.dev_major, f_stat.dev_minor ]
            t_stat = File.stat(File.dirname(to))
            t_dev  = [ t_stat.dev_major, t_stat.dev_minor ]
            if f_dev == t_dev
                # If file already exists we will need to unlink it before
                # but we will try to create hardlink before to not remove
                # it unnecessarily if hardlinks are not supported
                begin
                    File.link(from, to)
                    return true
                rescue Errno::EEXIST
                    # Don't catch exception unless forced
                    raise unless force
                    # File exist and we need to unlink it
                    # if unlink or link fails, something is wrong
                    begin
                        File.unlink(to)
                        File.link(from, to)
                        return true
                    rescue Errno::ENOENT
                        # That's ok we tried to unlink a file
                        # which didn't exists
                    end
                rescue Errno::EOPNOTSUPP
                    # If link are not supported fallback to copy
                end
            end
        end

        # Copy file
        op = force ? File::TRUNC : File::EXCL
        File.open(from, File::RDONLY) do |i|
            i.seek(offset)
            File.open(to, File::CREAT | File::WRONLY | op) do |o|
                IO.copy_stream(i, o, length)
            end
        end
        true
    rescue Errno::EEXIST
        false
    end


    # Create ROM object from file definition.
    #
    # If `file` is an absolute path or `root` is not specified,
    # ROM will be created with basename/dirname of entry.
    #
    # @param file [String]              path or relative path to file
    # @param root [String]              anchor for the relative entry path
    # @param headers [Array,nil,false]  header definition list
    #
    # @return [ROM]                     based on `file` content
    #
    def self.from_file(file, root = nil, headers: nil)
        basedir, entry = if    root.nil?             then File.split(file)
                         elsif file.start_with?('/') then File.split(file)
                         else                             [ root, file ]
                         end
        file           = File.join(basedir, entry)

        rominfo = File.open(file) { |io| ROM.info(io, headers: headers) }
        self.new(ROM::Path::File.new(entry, basedir), **rominfo)
    end


    # Create ROM representation.
    #
    # @param  path   [ROM::Path]                rom path
    # @param  size   [Integer]                  rom size
    # @param  offset [Integer,nil]              rom start (if headered)
    # @option cksums [String,Integer] :sha256   rom checksum using sha256
    # @option cksums [String,Integer] :sha1     rom checksum using sha1
    # @option cksums [String,Integer] :md5      rom checksum using md5
    # @option cksums [String,Integer] :crc32    rom checksum using crc32
    #
    def initialize(path, logger: nil, offset: nil, size: nil, **cksums)
        # Sanity check
        if path.nil?
            raise ArgumentError, "ROM path is required"
        end

        unsupported_cksums = cksums.keys - CHECKSUMS
        if !unsupported_cksums.empty?
            raise ArgumentError,
                  "unsupported checksums <#{unsupported_cksums.join(',')}>"
        end

        # Ensure checksum for nul-size ROM
        if size.zero?
            cksums = Hash[CHECKSUMS_DEF.map { |k, (_, z)| [ k, z ] }]
        end

        # Ensure offset for existing ROM size
        if !size.nil? && offset.nil?
            offset = 0 
        end
        
        # Initialize
        @path   = path
        @size   = size
        @offset = offset
        @cksum  = Hash[CHECKSUMS_DEF.map { |k, (s, _)|
            [ k, case val = cksums[k]
                 # No checksum
                 when '', '-', nil
                 # Checksum as hexstring or binary string
                 when String
                     case val.size
                     when s/4 then [ val ].pack('H*')
                     when s/8 then val
                     else raise ArgumentError,
                                "wrong size #{val.size} for hash string #{k}"
                     end
                 # Checksum as integer
                 when Integer
                     raise ArgumentError if (val < 0) || (val > 2**s)
                     [ "%0#{s/4}x" % val ].pack('H*')
                 # Oops
                 else raise ArgumentError, "unsupported hash value type"
                 end
            ]
        }].compact

        # Warns
        warns = []
#       warns << 'nul size'    if @size == 0
        warns << 'no checksum' if @cksum.empty?
        if !warns.empty?
            warn "ROM <#{self.to_s}> has #{warns.join(', ')}"
        end
    end


    # Compare ROMs using their checksums.
    #
    # @param o    [ROM]         other rom
    # @param weak [Boolean]     use weak checksum if necessary
    #
    # @return [Boolean]         if they are the same or not
    # @return [nil]             if it wasn't decidable due to missing checksum
    #
    def same?(o, weak: true)
        return true if self.equal?(o)

        decidable = false
        (weak ? CHECKSUMS : CHECKSUMS_STRONG).each { |type|
            s_cksum = self.cksum(type)
            o_cksum =    o.cksum(type)

            if s_cksum.nil? || o_cksum.nil? then next
            elsif s_cksum != o_cksum        then return false
            else                                 decidable = true
            end
        }
        decidable ? true : nil
    end


    # Check if ROM is virtual (no physical storage).
    # Usually storage is in a file or an archive file.
    #
    # @return [Boolean]
    #
    def virtual?
        @path.storage.nil?
    end


    # String representation.
    #
    # @param prefered [:name, :entry, :checksum]
    #
    # @return [String]
    #
    def to_s(prefered = :name)
        case prefered
        when :checksum
            if key = CHECKSUMS.find {|k| @cksum.include?(k) }
            then cksum(key, :hex)
            else name
            end
        when :name
            name
        when :entry
            entry
        else
            name
        end
    end


    # Does this ROM have an header?
    #
    # @return [Boolean]		Header present?
    # @return [nil]		ROM as not enough information
    #
    def headered?
        @offset&.positive?
    end


    # Get ROM header
    #
    # @return [String]		ROM header
    # @return [nil]		ROM as no header or not enough information
    #
    def header
        return nil unless headered?

        @path.reader { |io| io.read(@offset) }
    end


    # Get the ROM specific checksum
    #
    # @param type               checksum type must be one defined in CHECKSUMS
    # @param fmt [:bin,:hex]    checksum formating
    #
    # @return [String]          checksum value (either binary string
    #                           or as an hexadecimal string)
    #
    # @raise [ArgumentError]    if `type` is not one defined in {CHECKSUMS}
    #                           or `fmt` is not :bin or :hex
    #
    def cksum(type, fmt=:bin)
        raise ArgumentError unless CHECKSUMS.include?(type)

        if ckobj = @cksum[type]
            case fmt
            when :bin then ckobj
            when :hex then ckobj.unpack1('H*')
            else raise ArgumentError
            end
        end
    end


    # Get the ROM checksums
    #
    # @param fmt [:bin,:hex]    checksum formating
    #
    # @return [Hash{Symbol=>String}]    checksum
    #
    # @raise [ArgumentError]    if `type` is not one defined in {CHECKSUMS}
    #                           or `fmt` is not :bin or :hex
    #
    def cksums(fmt = :bin)
        case fmt
        when :bin then @cksum
        when :hex then @cksum.transform_values { |v| v.unpack1('H*') }
        else raise ArgumentError
        end
    end


    # Checksum to be used for naming on filesystem
    #
    # @return [String]          Checksum hexstring
    # @return [nil]		ROM has not enough information
    #
    def fshash
        cksum(FS_CHECKSUM, :hex)
    end


    # Get ROM offset in bytes.
    # Usually you want to use #headered? instead
    #
    # @return [Integer]         ROM offset in bytes
    # @return [nil]             ROM has not enough information
    #
    def offset
        @offset
    end


    # Get ROM size in bytes.
    #
    # @return [Integer]         ROM size in bytes
    # @return [nil]		ROM has not enough information
    #
    def size
        @size
    end


    # Check if ROM hold content.
    # @note Header is not considered as content.
    #
    # @return [Boolean]		ROM has content?
    # @return [nil]		ROM has not enough information
    #
    def empty?
        @size&.zero?
    end


    # Get ROM sha256 as hexadecimal string (if defined)
    #
    # @return [String]          hexadecimal checksum value
    # @return [nil]		ROM has not enough information
    #
    def sha256
        cksum(:sha256, :hex)
    end


    # Get ROM sha1 as hexadecimal string (if defined)
    #
    # @return [String]          Checksum hexstring
    # @return [nil]		ROM has not enough information
    #
    def sha1
        cksum(:sha1, :hex)
    end


    # Get ROM md5 as hexadecimal string (if defined)
    #
    # @return [String]          Checksum hexstring
    # @return [nil]		ROM has not enough information
    #
    def md5
        cksum(:md5, :hex)
    end


    # Get ROM crc32 as hexadcimal string (if defined)
    #
    # @return [String]          Checksum hexstring
    # @return [nil]		ROM has not enough information
    #
    def crc32
        cksum(:crc32, :hex)
    end


    # Get ROM info.
    # @note If offset start at 0, it is removed from returned data.
    #
    # @param cksum [:bin, :hex]         How checksum should be generated
    #
    # @return [Hash{Symbol=>Object]	ROM information
    #
    def info(cksum: :bin)
        cksums(cksum).merge(:size   => @size,
                            :offset => @offset&.zero? ? nil : @offset
                           ).compact
    end


    # Are all listed checksums defined?
    #
    # @param checksums [Array<Symbol>] list of checksums to consider
    #
    # @return [Boolean]
    #
    def checksums?(checksums = CHECKSUMS_DAT)
        (@cksum.keys & checksums) == checksums
    end


    # Get ROM name.
    #
    # @return [String]
    #
    def name
        @path.basename
    end


    # Get ROM path.
    #
    # @return [String]
    #
    def path
        @path
    end


    # ROM reader
    #
    # @yieldparam [#read] io            stream for reading
    #
    # @return block value
    #
    def reader(&block)
        @path.reader(&block)
    end


    # Copy ROM content to the filesystem, possibly using link if requested.
    #
    # @param to     [String]            file destination
    # @param length [Integer,nil]       data length to be copied
    # @param part   [:all,:header,:rom] which part of the rom file to copy
    # @param link   [:hard, :sym, nil]  use link instead of copy if possible
    #
    # @return [Boolean]                 status of the operation
    #
    def copy(to, part: :all, force: false, link: :hard)
        # Sanity check
        unless [ :all, :rom, :header ].include?(part)
            raise ArgumentError, "unsupported part (#{part})"
        end

        # Copy
        length, offset = case part
                         when :all
                             [ nil, 0 ]
                         when :rom
                             [ nil, @offset || 0 ]
                         when :header
                             return false unless self.headered?
                             [ @offset, 0 ]
                         end

        @path.copy(to, length, offset, force: force, link: link)
    end


    # Delete physical content.
    #
    # @return [Boolean]
    #
    def delete!
        if @path.delete!
            @path = ROM::Path::Virtual.new(@path.entry)
        end
    end


    # Rename ROM and physical content.
    #
    # @note Renaming could lead to silent removing if same ROM is on its way
    #
    # @param path  [String]             new ROM path
    # @param force [Boolean]            remove previous file if necessary
    #
    # @return [Boolean]                 status of the operation
    #
    # @yield                            Rename operation (optional)
    # @yieldparam old [String]          old entry name
    # @yieldparam new [String]          new entry name
    #
    def rename(path, force: false)
        # Deal with renaming
        ok = @path.rename(path, force: force)

        if ok
            @entry = entry
            yield(old_entry, entry) if block_given?
        end

        ok
    end
end

end


# SPDX-License-Identifier: EUPL-1.2

begin
    require 'libarchive'
rescue LoadError
    return
end


module Distillery
class Archiver

# Use binding to libarchive
#
class LibArchive < Archiver
    Archiver.add self

    MODE = { '7z'  => { :extensions =>  '7z',
                        :mimetypes  => 'application/x-7z-compressed' },
             'zip' => { :extensions => 'zip',
                        :mimetypes  => 'application/zip'             },
           }


    class InputStream < Archiver::InputStream
        def initialize(ar)
            @read_block = ar.to_enum(:read_data, 16*1024)
            @buffer     = StringIO.new
        end


        def read(length = nil)
            return ''  if length&.zero?         # Zero length request
            return nil if @buffer.nil?          # End of stream

            # Read data
            data = @buffer.read(length) || ''
            while data.size < length
                # We are short on data, that means buffer has been exhausted
                # request new data block from the archive
                block = @read_block.next
                # Break if we already read all the archive data
                if block.nil? || block.empty?
                    @buffer = nil
                    break
                end
                # Refill buffer from block
                @buffer.string = block
                # Continue reading
                data.concat(@buffer.read(length - data.size))
            end

            data.empty? ? nil : data
        end
    end


    def self.registering
        MODE.each_key do |mode|
            Archiver.register(LibArchive.new(mode))
        end
    end


    def initialize(mode)
        raise ArgumentError unless MODE.include?(mode)

        @mode = mode
    end


    # List of supported extensions
    #
    def extensions
        MODE[@mode][:extensions]
    end


    # List of supported mimetypes
    #
    def mimetypes
        MODE[@mode][:mimetypes]
    end


    # (see Archiver#each)
    def each(file)
        ::Archive.read_open_filename(file) do |ar|
            while (a_entry = ar.next_header)
                next unless a_entry.regular?
                $stdout.puts a_entry.pathname
                yield(a_entry.pathname, InputStream.new(ar))
            end
        end
        self
    end

end


end
end

# SPDX-License-Identifier: EUPL-1.2

begin
    require 'zip'
rescue LoadError
    return
end


module Distillery
class Archiver

# Use of rubyzip as archiver
#
class Zip < Archiver
    Archiver.add self


    # Perform registration of the various archive format
    # supported by this archiver provider
    #
    # @return [void]
    #
    def self.registering
        Archiver.register(Zip.new)
    end


    def initialize
    end


    # (see Archiver#extensions)
    def extensions
        [ 'zip' ]
    end


    # (see Archiver#mimetypes)
    def mimetypes
        [ 'application/zip' ]
    end


    # (see Archiver#delete!)
    def delete!(file, entry)
        ::Zip::File.open(file) do |zip_file|
            zip_file.remove(entry) ? true : false
        end
    rescue Errno::ENOENT
        false
    rescue ::Zip::Error => e
        raise ProcessingError
    end


    # (see Archiver#reader)
    def reader(file, entry)
        ::Zip::File.open(file) do |zip_file|
            zip_file.get_input_stream(entry) do |is|
                yield(InputStream.new(is))
            end
        end
    rescue ::Zip::Error => e
        raise ProcessingError
    end


    # (see Archiver#writer)
    def writer(file, entry)
        ::Zip::File.open(file, ::Zip::File::CREATE) do |zip_file|
            zip_file.get_output_stream(entry) do |os|
                yield(OutputStream.new(os))
            end
        end
    rescue ::Zip::Error => e
        raise ProcessingError
    end


    # (see Archiver#each)
    def each(file)
        return to_enum(:each, file) unless block_given?

        ::Zip::File.open(file) do |zip_file|
            zip_file.each do |zip_entry|
                next unless zip_entry.ftype == :file
                yield(zip_entry.name,
                      InputStream.new(zip_entry.get_input_stream))
            end
        end
    rescue ::Zip::Error => e
        raise ProcessingError
    end

end

end
end


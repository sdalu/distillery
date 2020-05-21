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
        ::Zip::File.open(file) {|zip_file|
             zip_file.remove(entry) ? true : false
        }
    rescue Errno::ENOENT
        false
    end

    # (see Archiver#reader)
    def reader(file, entry, &block)
        ::Zip::File.open(file) {|zip_file|
            zip_file.get_input_stream(entry) {|is|
                block.call(InputStream.new(is))
            }
        }
    end

    # (see Archiver#writer)
    def writer(file, entry, &block)
        ::Zip::File.open(file, ::Zip::File::CREATE) {|zip_file|
            zip_file.get_output_stream(entry) {|os|
                block.call(OutputStream.new(os))
            }
        }
    end 

    # (see Archiver#each) 
    def each(file, &block)
        return to_enum(:each, file) if block.nil?
        ::Zip::File.open(file) {|zip_file|
            zip_file.each {|zip_entry|
                next unless zip_entry.ftype == :file
                block.call(zip_entry.name,
                           InputStream.new(zip_entry.get_input_stream))
            }
        }
    end

end

end
end


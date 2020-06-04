# SPDX-License-Identifier: EUPL-1.2

require 'psych'
require 'time'

module Distillery

# Handle information from DAT file
class IndexFile
    class ContentError < Error
    end

    include Enumerable

    def each
        block_given? ? @roms.each { |r| yield(r) }
                     : @roms.each
    end
    
    def initialize(file, sanity: true)
        dir  = File.dirname(file)
        data = Psych.load_file(file)
        raise ContentError unless data.instance_of?(Hash)

        archives = {}
        in_sync  = true
        @roms    = Vault.new
        
        data.each do |file, meta|
            # Extract ROM info and timestamp
            info      = meta.transform_keys(&:to_sym)
            timestamp = Time.parse(info.delete(:timestamp))

            # Build ROM description
            a_file, a_entry = ROMArchive.parse_path(file)
            rom = if a_file
                      a_file = File.join(dir, a_file)
                      if a_file.start_with?(".#{File::SEPARATOR}")
                          a_file = a_file[(File::SEPARATOR.size+1)..-1]
                      end
                      
                      archive = archives[a_file] ||=  ROMArchive.new(a_file)
                      path    = ROM::Path::Archive.new(archive, a_entry)
                      archive[a_entry] = ROM.new(path, **info)
                  else
                      ROM.new(ROM::Path::File.new(file, dir), **info)
                  end

            # Add rom to vault
            @roms.add_rom(rom)
            
            # Check timestamp
            in_sync &&=  File.exists?(rom.path.storage) &&
                         (File.mtime(rom.path.storage) == timestamp)            
        end

        if sanity && !in_sync
            warn "index file #{file} is out of sync"
        end
        
    rescue Psych::SyntaxError
        raise ContentError, "YAML/JSON file required"
    end

    
    attr_reader :roms
    
end

end

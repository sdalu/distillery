# SPDX-License-Identifier: EUPL-1.2

require_relative 'vault'

module Distillery

class Storage
    include Enumerable

    # Hidden ROMs directory
    ROMS_DIR  = '.roms'

    # Hidden games directory
    GAMES_DIR = '.games'


    def initialize(vault)
        @roms = vault
    end


    def headered
        @roms.headered
    end


    def each
        block_given? ? @roms.each { |r| yield(r) }
                     : @roms.each
    end


    def index(separator = nil)
        each.map { |rom|
            cksums = rom.cksums(:hex)
            file   = case path = rom.path
                     when ROM::Path::Archive then path.to_s(separator)
                     else                         path.to_s
                     end
            data   = cksums.merge(:size     => rom.size,
                                  :headered => rom.headered? || nil).compact
            [ file,  data ]
        }
    end


    def build_roms_directory(dest, pristine: false, force: false, delete: false)
        block = if delete
                    proc { |rom, copied:, **|
                        rom.delete! if copied
                    }
                end
        @roms.save(dest,
                   part: :rom, subdir: true, pristine: pristine, force: force,
                   &block)
        self
    end


    def build_games(dat, vault)
        dat.games.each do |game|
            puts "Building: #{game}"

            game.roms.each do |rom|
                # Find in the matching ROM in the storage vault
                # Note that in the vault:
                #   - the same ROM can be present multiple time
                #   - all checksums are defined
                match = Array(vault.match(rom))
                            .uniq { |r| r.cksum(FS_CHECKSUM) }

                # Sanity check
                if    match.size > 1
                    # Due to weak ROM definition in DAT file
                    puts "- multiple matching ROMs for #{rom} (IGNORING)"
                    next
                elsif match.size == 0
                    # Sadly we don't have this ROM
                    puts "- no mathing ROM for #{rom} (IGNORING)"
                    next
                end

                # Get vault ROM
                vrom = match.first

                # Call block
                yield(game.name, vrom, rom.path.entry)
            end
        end
    end


    def build_games_directories(dir, dat, vault, pristine: false, force: false)
        # Directory
        Dir.unlink(dir) if     pristine		# Create clean env if requested
        Dir.mkdir(dir)  unless Dir.exist?(dir)  # Ensure directory exists

        # Build game directories
        build_games(dat, vault) {|game, rom, dst|
            rom.copy(File.join(dir, game, dst))
        }
    end


    def build_games_archives(dir, dat, vault, type = '7z', pristine: false)
        # Normalize to lower case
        type = type.downcase

        # Directory
        Dir.unlink(dir) if     pristine		# Create clean env if requested
        Dir.mkdir(dir)  unless Dir.exist?(dir)  # Ensure directory exists

        # Ensure we support this type of archive
        if !ROMArchive::EXTENSIONS.include?(type)
            raise ArgumentError, "unsupported type (#{type})"
        end

        # Build game archives
        build_games(dat, vault) do |game, rom, dst|
            file = File.join(dir, "#{game}.#{type}")
            Distillery::Archiver.for(file).writer(dst) do |o|
                rom.reader do |i|
                    while data = i.read(32 * 1024)
                        o.write(data)
                    end
                end
            end
        end
    end



    def rename(dat)
        @roms.each do |rom|
            # Skip if ROM is not present in DAT ?
            if (m = dat.roms.match(rom)).nil?
                puts "No DAT rom matching <#{rom}>"
                next
            end

            # Find new rom name
            name = if m.size == 1
                       # Easy, take the DAT rom name if different
                       next if m.first.name == rom.name
                       m.first.name
                   else
                       # Find name in the DAT, that is not currently present
                       # in our vault for this rom.
                       match_name = m.map { |r| r.name }
                       roms_name  = @roms.match(rom).map { |r| r.name }
                       lst_name   = match_name - roms_name

                       # Check if all DAT names are present in our vault,
                       # but perhaps we have an extra name to be removed
                       if lst_name.empty?
                           if (roms_name - match_name).include?(rom.name)
                               rom.delete!
                           end
                           next
                       end

                       # Use the first name
                       lst_name.first
                   end

            # Apply new name. (Will be a no-op if same name)
            rom.rename(name) { |old_name, new_name|
                puts "  < #{old_name}"
                puts "  > #{new_name}"
            }
        end
    end


    attr_reader :roms

end

end


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


    def build_roms_directory(dest, pristine: false, force: false, delete: false)
        block = if delete
                    proc { |rom, copied:, **|
                        rom.delete! if copied
                    }
                end
        @roms.copy(dest,
                   part: :rom, subdir: true, pristine: pristine, force: force,
                   &block)
        self
    end


    # Extract headers
    def extract_headers(destdir)
        @roms.copy(destdir, part: :header, force: @force) do |rom, as:, copied:, **|
            yield(rom, as: as, copied: copied)
        end
    end
    

    # Check the vault for an exact match with the DAT.
    #
    # @param dat        [DatFile]               DAT file.
    # @param included   [#<<, #call]            Accumulator for included
    # @param missing    [#<<, #call]            Accumulator for missing
    # @param extra      [#<<, #call]            Accumulator for extra
    #
    # @return [Boolean] perfect match
    #
    # @yieldparam group   [String]
    # @yieldparam entries [Array<String>]
    #
    def check(dat, included: nil, missing: nil, extra: nil)
        importer = ->(holder, vault) do
            return if holder.nil?
            vault.dump(compact: true) do |storage, entries|
                if    holder.respond_to?(:<<)
                    holder << [ storage, entries ]
                elsif holder.respond_to?(:call)
                    holder.call(storage, entries)
                else raise ArgumentError, "must respond to << or call"
                end
            end
        end

        no_missing = if missing
                         (dat.roms - @roms).tap {|roms|
                             importer.(missing, roms)
                         }.empty?
                     end
        no_extra   = if extra
                         (@roms - dat.roms).tap {|roms|
                             importer.(extra, roms)
                         }.empty?
                     end        
        perfect    = if included || (missing.nil? || extra.nil?)
                         (dat.roms & @roms).tap {|roms|
                             importer.(included, roms)
                         }.size == dat.roms.size
                     end

        # Have we a perfect match ?
        perfect || (no_missing && no_extra)
    end


    # Validate ROMs according to DAT/Index file.
    #
    # @param dat        [DatFile]               DAT file.
    #
    def validate(dat)
        stats   = { :not_found         => 0,
                    :missing_duplicate => 0,
                    :name_mismatch     => 0,
                    :wrong_place       => 0 }
        checker = lambda { |game, rom|
            m = @roms.match(rom)

            # Not found
            if m.nil? || m.empty?
                stats[:not_found] += 1
                'not found'

            # Found with a different name:
            #  - name mismatch
            #  - rom exist but was not duplicated with the wanted named
            elsif m.select {|r| r.name == rom.name }.empty?
                # If all matching ROMs in vault have their name in the dat
                # file, it's a missing duplicated
                # Note: we need to check that the list of name matching roms
                #       returned from the dat file hold our rom indeed.
                unused = m.select {|r|
                    dat.lookup(r.name)&.any? {|rom| rom.same?(r) }
                }
                if unused.empty?
                    stats[:name_mismatch] += 1
                    'name mismatch' +
                        (m.size == 1 ? " (#{m[0].name})" : '')
                else
                    stats[:missing_duplicate] += 1
                    'missing duplicate'
                end
                
            # Found in a different path
            #  - name mismatch
            #  - rom exist but was not duplicated with the wanted named
            elsif m.select {|r|
                      store = File.basename(r.path.storage)
                      ROMArchive::EXTENSIONS.any? {|ext|
                          ext = Regexp.escape(ext)
                          store.gsub(/\.#{ext}$/i, '') == game.name
                      } || (store == game.name) || source.include?(store)
                  }.empty?
                stats[:wrong_place] += 1
                'wrong place'
            end
        }

        dat.each_game do |game|
            errors, count = 0, 0
            yield(:game => game, :start => true)
            game.each_rom do |rom|
                yield(:rom => rom, :start => true)
                count  += 1
                errors += 1 if error = checker.call(game, rom)
                yield(:rom => rom, :end => true, :error => error)
            end
            yield(:game => game, :end => true,
                  :errors => errors, :count => count)
        end

        stats
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


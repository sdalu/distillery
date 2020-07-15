# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Index < Command
    DESCRIPTION = 'Generate vault index'
    OUTPUT_MODE = [ :text, :yaml, :json ]

    # Parser for index command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [-p] ROMDIR...\n" \
                      "       #{PROGNAME} #{self} -c|-r|-u [-I] [-y|-j] ROMDIR"

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION} (filename and metadata)."
        opts.separator ''
        opts.separator 'The generated index file can later be refreshed ' \
                       '(only consider ROM present'
        opts.separator 'in the index file) or updated (will also add ' \
                       'missing ROMs available'
        opts.separator 'in file system or archives).'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-p', '--path-strip=INTEGER', Integer,
                "Pathname strip count" do |v|
            raise Error, "path-strip value must be >= 0" if v.negative?
            v
        end
        opts.on '-I', '--index=name',
                "In-folder index name (default: #{INDEX})" do |v|
            if v&.include?(File::SEPARATOR)
                raise Error, "index file name should contain no base directory"
            end
            v
        end
        opts.on '-c', '--create',  'Create index file'
        opts.on '-r', '--refresh', 'Refresh index file (delete/update)'
        opts.on '-u', '--update',  'Update index file (add/delete/update)'
        opts.on '-y', '--yaml',    'Produce YAML index (default)'
        opts.on '-j', '--json',    'Produce JSON index'
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ {    sha256: "<hexstring>",'                \
                       '           sha1: "<hexstring>",'
        opts.separator '            md5: "<hexstring>",'                \
                       '          crc32: "<hexstring>",'
        opts.separator '           size: <integer>,    '                \
                       '        ?offset: <integer>,'
        opts.separator '      timestamp: "<timestamp>"'
        opts.separator '    }, ... ]'
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} -c romdir   " 		\
                       "# Create Index"
        opts.separator "$ #{PROGNAME} #{self} -u romdir   "		\
                       "# Update existing Index"
        opts.separator "$ #{PROGNAME} #{self} -p1 romdir  "		\
                       "# Generate textual Index (striping first-directory)"
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        romdirs = argv
        opmode  = opts.keys & [ :refresh, :update, :create ]
        
        # Deal with index on stdout
        if opmode.empty?
            # Sanity check CLI arguments
            if romdirs.empty?
                raise Error, "at least one directory is required"
            end
            if opts.include?(:index)
                raise Error, 'option --index only supported with' 	\
                             ' --update, --refresh, or --create'
            end
            if opts.include?(:yaml) || opts.include?(:json)
                raise Error, 'option --yaml or --json only supported with' \
                             ' --update, --refresh, or --create'
            end

            # Generate index
            index(romdirs, pathstrip: opts[:'path-strip'])

        # Deal with index create/refresh/update
        else
            # Sanity check CLI arguments
            if opmode.size > 1
                raise Error, '--update, --refresh, --create are' 	\
                             ' mutually exclusive'
            elsif !romdirs.one?
                raise Error, 'exactly one directory is required' 	\
                             ' with --update, --refresh, or --create'
            elsif opts.include?(:'path-strip')
                raise Error, '--path-strip not supported with' 		\
                             ' --update, --refresh, or --create'
            elsif opts.include?(:yaml) && opts.include?(:json)
                raise Error, '--yaml and --json are mutually exclusive'
            end

            #  Validate presence/absence of index file
            index   = opts[:index] || INDEX
            basedir = romdirs[0]
            file    = File.join(basedir, index)
            type = if    opts[:json] then :json
                   elsif opts[:yaml] then :yaml
                   end
            if opts.include?(:refresh) || opts.include?(:update)
                unless File.exists?(file)
                    raise Error, "index file doesn't exists (#{file})"
                end
                # Try guessing type if not already required
                type ||= case File.read(file, 4)
                         when "---\n"   then :yaml
                         when /^[\{\[]/ then :json
                         end
            elsif opts.include?(:create)
                if File.exists?(file) && !@cli.force
                    raise Error, "file #{file} exists (use --force)"
                end
            end

            # Ensure default type
            type ||= :yaml
            
            # Perform index operation
            Dir.chdir(basedir) do
                if opts.include?(:refresh)
                    update(index, adding: false, type: type)
                elsif opts.include?(:update)
                    update(index, adding: true,  type: type)
                elsif opts.include?(:create)
                    index(['.'], file: index,    type: type)
                end
            end
        end
    end


    # Update existing index file
    #
    # @param index_file [String]	index file
    # @param adding     [Boolean]	also perform adding of new file
    # @param type       [:yaml,:json]	select output format
    #
    def update(index_file, adding: true, type: :yaml)
        updated = false
        
        # Load vault from index discarding out of sync ROMs
        # but keep track of them (file and path)
        files_changed = {}
        oos_proc      = lambda do |rom|
            (files_changed[rom.path.file] ||= []) << rom.path
            false   # Reject
        end
        vault = Vault.load(index_file, out_of_sync: oos_proc)

        # Remove missing files and notify
        files_changed.select! do |file, paths|
            File.exists?(file).tap { |exist|
                unless exist
                    paths.each do |path|
                        updated = true
                        warn "REMOVE: #{path}"
                    end
                end
            }
        end

        # File has changed
        files_changed.each do |file, paths|
            # Update from ROM Archive
            if ROMArchive.archive?(file)
                # Build mapping between entry and path
                # (it is unique inside an archive)
                entries = paths.to_h {|path| [ path.entry, path ] }

                # Keep track of new entries
                added = Set.new
                
                # Build ROM Archive from file
                rom_archive = ROMArchive.from_file(file) {|entry|
                    # Check if entry is new, add build removed list
                    new_entry = entries.delete(entry).nil?
                    # Keep track if new entry if adding required
                    added    << entry if adding && new_entry
                    # If entry is new and adding not required, discard it here.
                    adding || !new_entry
                }
                # Notify of entries that where removed
                entries.each {|entry, path|
                    updated = true
                    warn "REMOVE: #{path}"
                }
                # Update from existing entries
                rom_archive.each {|rom|
                    updated = true
                    if adding && added.include?(rom.path.entry)
                    then warn "ADD   : #{rom.path}"
                    else warn "UPDATE: #{rom.path}"
                    end
                    vault.add_rom(rom)
                }

            # Update from ROM file
            else
                updated = true
                warn "UPDATE: #{paths.first}"
                rom = ROM.from_file(file)
                vault.add_rom(rom)
            end
        end

        # If adding deal with new files 
        if adding
            # Retrieve list of files effectively loaded
            files_on_vault = Set.new(vault.map {|rom| rom.path.file })

            # Scan directory holding index file for available ROMs
            files_on_disk  = Set.new
            @cli.from_romdirs([ File.dirname(index_file) ]) do | f, dir: |
                file = File.join(dir, f)
                file = file[2..-1] if file.start_with?(".#{File::SEPARATOR}")
                files_on_disk << file
            end

            # Set of file not processed
            (files_on_disk - files_on_vault).each do |file|
                # Update from ROM Archive
                if ROMArchive.archive?(file)
                    ROMArchive.from_file(file).each do |rom|
                        updated = true
                        warn "ADD   : #{rom.path}"
                        vault.add_rom(rom)
                    end
                    
                # Update from ROM file
                else
                    updated = true
                    rom = ROM.from_file(file)
                    warn "ADD   : #{rom.path}"
                    vault.add_rom(rom)
                end
            end
        end

        if updated
            vault.save(index_file, type: type)
        else
            warn "Index is already up to date"
        end
    end

    
    
    # Print vault index (hash and path of each ROM)
    #
    # @param romdirs    [Array<String>]   ROMs directories
    # @param pathstrip  [Integer,nil]     Strip path from the first directories
    # @param file       [String]	  index file
    # @param type       [:yaml,:json,nil] select output format
    #
    def index(romdirs, type: nil, file: nil, pathstrip: nil)
        file ||= @cli.io
        type ||= @cli.output_mode

        # Generating index can be quite long, don't trash all data
        # in case a file processing failure, but notify at the end
        failed_set  = Set.new
        failed_proc = lambda {|file| failed << file ; false }

        # Generate index
        @cli.vault(romdirs, failed: failed_proc)
            .save(file, type: type,
                   pathstrip: pathstrip,
                     skipped: ->(path) { warn "SKIPPED: #{path}" } )

        # Notify in case of processing file failure
        unless failed_set.empty?
            warn "Unable to process the following files:"
            failed_set.each {|file|
                warn "- #{file}"
            }
        end
    end

end

end
end

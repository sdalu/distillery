# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    def rebuild(gamedir, datfile, romdirs, type = nil)
        # Select archive type if not specified
        type      ||= ROMArchive::PREFERED


        dat     = make_dat(datfile)
        storage = make_storage(romdirs)

        # gamedir can be one of the romdir we must find a clever
        # way to avoid overwriting file

        romsdir = File.join(gamedir, '.roms')
        storage.build_roms_directory(romsdir, delete: true)

        vault = Vault.new
        vault.add_from_dir(romsdir)

        storage.build_games_archives(gamedir, dat, vault, type)
        FileUtils.remove_dir(romsdir)
    end

    # -----------------------------------------------------------------


    # Parser for header command
    RebuildParser = OptionParser.new do |opts|
        types = ROMArchive::EXTENSIONS.to_a
        opts.banner = "Usage: #{PROGNAME} rebuild [options] ROMDIR..."
        opts.separator ''
        opts.separator 'Rebuild ROMs to match DAT file' 		\
                       ' (renaming ROM and removing extra data).'
        opts.separator 'WARN: non-matching ROM will be removed.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-F', '--format=FORMAT', types,
                "Archive format (#{ROMArchive::PREFERED})",
                " Value: #{types.join(', ')}"
        opts.separator ''
    end


    # Register rebuild command
    subcommand :rebuild, 'Rebuild according to DAT file',
               RebuildParser do |argv, **opts|
        opts[:romdirs] = argv
        if opts[:dat].nil? && (opts[:romdirs].size >= 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end

        if opts[:destdir].nil? && (opts[:romdirs].size >= 1)
            opts[:destdir] = opts[:romdirs].first
        end

        [ opts[:destdir], opts[:dat], opts[:romdirs], opts[:format] ]
    end

end
end

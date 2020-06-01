# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    def rebuild(gamedir, datfile, romdirs)
        dat     = make_dat(datfile)
        storage = make_storage(romdirs)

        # gamedir can be one of the romdir we must find a clever
        # way to avoid overwriting file

        romsdir = File.join(gamedir, '.roms')
        storage.build_roms_directory(romsdir, delete: true)

        vault = ROMVault.new
        vault.add_from_dir(romsdir)

        storage.build_games_archives(gamedir, dat, vault, '7z')
        FileUtils.remove_dir(romsdir)
    end

    # -----------------------------------------------------------------


    # Parser for header command
    RebuildParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} rebuild ROMDIR..."
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

        [ opts[:destdir], opts[:dat], opts[:romdirs] ]
    end

end
end

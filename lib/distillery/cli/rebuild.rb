# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Rebuild < Command
    DESCRIPTION = 'Rebuild according to DAT file'
    
    # Parser for rebuild command
    Parser = OptionParser.new do |opts|
        types = ROMArchive::EXTENSIONS.to_a

        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION} (renaming ROM and removing extra data)."
        opts.separator 'WARN: non-matching ROM will be removed.'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-F', '--format=FORMAT', types,
                "Archive format (#{ROMArchive::PREFERED})",
                " Value: #{types.join(', ')}"
        opts.separator ''
        
        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir                " \
                       "# Rebuild using .dat in romdir"
    end

    # (see Command#run)
    def run(argv, **opts)
        romdirs = retrieve_romdirs!(argv)
        datfile = retrieve_datfile!(opts[:dat    ], romdirs)
        destdir = retrieve_destdir!(opts[:destdir], romdirs, dirname: 'Rebuild')
        format  = opts[:format]
        
        rebuild(destdir, datfile, romdirs, format)
    end

    def rebuild(gamedir, datfile, romdirs, type = nil)
        # Select archive type if not specified
        type      ||= ROMArchive::PREFERED


        dat     = @cli.dat(datfile)
        storage = @cli.storage(romdirs)

        # gamedir can be one of the romdir we must find a clever
        # way to avoid overwriting file

        romsdir = File.join(gamedir, '.roms')
        storage.build_roms_directory(romsdir, force: true, delete: true)

        vault = Vault.new
        vault.add_from_dir(romsdir)

        storage.build_games_archives(gamedir, dat, vault, type)
        FileUtils.remove_dir(romsdir)
    end

end

end
end

# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Rebuild < Command
    DESCRIPTION = 'Rebuild according to DAT file'
    
    # Parser for rebuild command
    Defaults = { :format => ROMArchive::PREFERED }
    Parser   = OptionParser.new do |opts|
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
        opts.on '-D', '--dat=FILE',        "DAT file"
        opts.on '-d', '--destdir=DIR',     "Rebuild directory"
        opts.on '-F', '--format=FORMAT', types,
                "Archive format (default: #{Defaults[:format]})",
                " Values: #{types.join(', ')}"
        opts.separator ''
        
        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir                " \
                       "# Rebuild using .dat in romdir"
        opts.separator "$ #{PROGNAME} #{self} -d out romdir         " \
                       "# Rebuild to out directory"
    end

    # (see Command#run)
    def run(argv, **opts)
        romdirs = retrieve_romdirs! argv
        datfile = retrieve_datfile! opts[:dat    ], romdirs
        destdir = retrieve_destdir! opts[:destdir], romdirs, dirname: 'Rebuild'
        format  = opts[:format]
        
        rebuild(destdir, datfile, romdirs, format)
    end

    def rebuild(destdir, datfile, romdirs, type = ROMArchive::PREFERED)
        dat      = @cli.dat(datfile)
        storage  = @cli.storage(romdirs)

        # destdir can be one of the romdir we must find a clever
        # way to avoid overwriting file

        romdir = File.join(destdir, '.roms')
        storage.build_roms_directory(romdir, force: true, delete: true)

        vault = Vault.new
        vault.add_from_dir(romdir)

        storage.build_games_archives(destdir, dat, vault, type)
        FileUtils.remove_dir(romdir)
    end

end

end
end

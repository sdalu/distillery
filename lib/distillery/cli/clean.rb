# SPDX-License-Identifier: EUPL-1.2

module Distillery

class CLI

    def clean(datfile, romdirs, savedir: nil)
        dat        = make_dat(datfile)
        storage    = make_storage(romdirs)
        extra      = storage.roms - dat.roms

        extra.save(savedir) if savedir
        extra.each(&:delete!)

        # Allows chaining
        self
    end


    # -----------------------------------------------------------------


    # Parser for clean command
    CleanParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} clean [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Remove content not referenced in DAT file'
        opts.separator ''
    end

    # Register clean command
    subcommand :clean, 'Remove content not referenced in DAT file',
               CleanParser do |argv, **opts|
        opts[:romdirs] = ARGV
        if opts[:dat].nil? && (opts[:romdirs].size == 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:destdir].nil? && (opts[:romdirs].size == 1)
            opts[:destdir] = File.join(opts[:romdirs].first, '.trash')
        end

        if opts[:dat].nil?
            warn "missing datfile"
            exit
        end
        if opts[:romdirs].empty?
            warn "missing ROM directory"
            exit
        end
        if opts[:destdir].empty?
            warn "missing save directory"
            exit
        end

        [ opts[:dat], opts[:romdirs], savedir: opts[:destdir] ]
    end

end
end

# SPDX-License-Identifier: EUPL-1.2

module Distillery

class CLI

    def clean(datfile, romdirs, savedir: nil)
        dat        = make_dat(datfile)
        storage    = make_storage(romdirs)
        extra      = storage.roms - dat.roms

        extra.save(savedir) if savedir
        extra.each(&:delete!)
    end


    # -----------------------------------------------------------------


    # Parser for clean command
    CleanParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} clean [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Remove content not referenced in DAT file'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-s', '--summarize', "Summarize results"
        opts.separator ''
    end

    # Register clean command
    subcommand :clean, 'Remove content not referenced in DAT file',
               CleanParser do |argv, **opts|
        opts[:romdirs] = ARGV
        if opts[:dat].nil? && (opts[:romdirs].size == 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:savedir].nil? && (opts[:romdirs].size == 1)
            opts[:savedir] = File.join(opts[:romdirs].first, '.trash')
        end

        if opts[:dat].nil?
            warn "missing datfile"
            exit
        end
        if opts[:romdirs].empty?
            warn "missing ROM directory"
            exit
        end
        if opts[:savedir].empty?
            warn "missing save directory"
            exit
        end

        [ opts[:dat], opts[:romdirs], savedir: opts[:savedir] ]
    end

end
end

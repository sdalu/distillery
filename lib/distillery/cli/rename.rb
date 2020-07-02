# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Rename < Command

    DESCRIPTION = 'Rename ROMs according to DAT'

    Parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator ''
    end

    
    def rename(datfile, romdirs)
        dat     = @cli.dat(datfile)
        storage = @cli.storage(romdirs)

        storage.rename(dat)
    end

    # -----------------------------------------------------------------


    # Register rename command
    def run(argv, **opts)
        opts[:romdirs] = argv
        if opts[:dat].nil? && (opts[:romdirs].size == 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:dat].nil?
            warn 'missing datfile'
            exit
        end
        if opts[:romdirs].empty?
            warn 'missing ROM directory'
            exit
        end

        rename(opts[:dat], opts[:romdirs])
    end

end

end
end

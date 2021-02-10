# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Rename < Command

    DESCRIPTION = 'Rename ROMs according to DAT'

    # Parser for rename command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator ''
    end

    
    # (see Command#run)
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

    
    # Rename ROMs according to DAT file
    #
    # @param datfile    [String]                DAT file    
    # @param romdirs    [Array<String>]         ROMs directories
    #
    def rename(datfile, romdirs)
        dat     = @cli.dat(datfile)
        storage = @cli.storage(romdirs)

        storage.rename(dat)
    end
end

end
end

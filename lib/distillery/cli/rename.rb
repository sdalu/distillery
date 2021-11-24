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
        romdirs   = retrieve_romdirs!  argv
        datfile   = retrieve_datfile!  opts[:dat    ], romdirs
        indexfile = retrieve_indexfile opts[:index  ], romdirs

        rename(datfile, indexfile || romdirs)
    end

    
    # Rename ROMs according to DAT file
    #
    # @param datfile    [String]                DAT file    
    # @param romdirs    [Array<String>]         ROMs directories
    # @param romdirs    [String]                Index file
    #
    def rename(datfile, source)
        dat     = @cli.dat(datfile)
        storage = @cli.storage(source)

        storage.rename(dat)
    end
end

end
end

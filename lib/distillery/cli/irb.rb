# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Irb < Command
    DESCRIPTION = 'Start ruby debugger session'
    STATUS      = :okay

    # Parser for index command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} irb [ROMDIR...]"

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-I', '--[no-]index[=FILE]', "Index file"
        opts.on '-D', '--dat=FILE',          "DAT file"
    end


    # (see Command#run)
    def run(argv, **opts)
        begin
            $romdirs   = retrieve_romdirs!  argv
            $indexfile = retrieve_indexfile opts[:index  ], $romdirs
            $datfile   = retrieve_datfile!  opts[:dat    ], $romdirs
        rescue Error
        end

        require 'irb'

        puts "Welcome to IRB session"
        puts 
        puts "$romdirs   [%c]: List of ROMs directory" % [ $romdirs  ? 'x':' ' ]
        puts "$datfile   [%c]: Path to DAT file"       % [ $datfile  ? 'x':' ' ]
        puts "$indexfile [%c]: Path to Index file"     % [ $indexfile? 'x':' ' ]
        puts
        
        ARGV.clear
        IRB.start
    end

end

end
end

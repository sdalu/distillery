# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI
        
class Check < Command
    DESCRIPTION = 'Check ROM status'
    
    # Parser for check command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} check [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION} (display missing or extra files)."
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-r', '--revert', 'Display present files instead'
        opts.on '-I', '--[no-]index[=FILE]', "Index file"
        opts.on '-D', '--dat=FILE',          "DAT file"
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir                " \
                       "# Look for .dat in romdir"
        opts.separator "$ #{PROGNAME} #{self} -D foo.dat romdir     " \
                       "# Look for foo.dat in romdir"
        opts.separator "$ #{PROGNAME} #{self} -D ./foo.dat romdir   " \
                       "# Look for foo.dat in current directory"
    end

    
    # (see Command#run)
    def run(argv, **opts)
        romdirs   = retrieve_romdirs!  argv
        datfile   = retrieve_datfile!  opts[:dat    ], romdirs
        indexfile = retrieve_indexfile opts[:index  ], romdirs
        show      = opts[:show]
        
        check(datfile, indexfile || romdirs, show)
    end

    # Check that the ROM directories form an exact match of the DAT file
    #
    # @param datfile    [String]                DAT file
    # @param source     [Array<String>]         ROMs directories
    # @param source     [String]                Index file
    # @param revert	[Boolean]		Display present ROMs instead
    #
    def check(datfile, source, revert: false)
        io     = @cli.io
        dat    = @cli.dat(datfile)
        vault  = @cli.vault(source)

        missing  = dat.roms - vault
        extra    = vault - dat.roms
        included = dat.roms & vault

        printer  = proc { |entry, subentries|
            io.puts "- #{entry}"
            Array(subentries).each { |entry| io.puts "  . #{entry}" }
        }

        # Warn about presence of headered ROM
        if vault.headered
            warn '===> Headered ROM'
        end


        # Show included ROMs
        if revert
            if included.empty?
                io.puts "==> No rom included"
            else
                io.puts "==> Included roms (#{included.size}):"
                included.dump(compact: true, &printer)
            end

        # Show missing and extra ROMs
        else
            unless missing.empty?
                io.puts "==> Missing roms (#{missing.size}):"
                missing.dump(compact: true, &printer)
            end
            io.puts if !missing.empty? && !extra.empty?
            unless extra.empty?
                io.puts "==> Extra roms (#{extra.size}):"
                extra.dump(compact: true, &printer)
            end
        end

        # Have we a perfect match ?
        if missing.empty? && extra.empty?
            io.puts '==> PERFECT'
        end
    end

end

end
end

# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI
        
class Check < Command
    DESCRIPTION = 'Check ROM status'
    
    # Parser for check command
    Parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} check [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Check ROMs status, and display missing or extra files.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-r', '--revert', 'Display present files instead'
        opts.separator ''
    end

    
    # (see Command#run)
    def run(argv, **opts)
        opts[:romdirs] = argv
        if opts[:dat].nil? && (opts[:romdirs].size >= 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:dat].nil?
            raise Error, "missing datfile"
        end
        if opts[:romdirs].empty?
            raise Error, "missing ROM directory"
        end

        check(opts[:dat], opts[:romdirs], revert: opts[:revert] || false)
    end

    # Check that the ROM directories form an exact match of the DAT file
    #
    # @param datfile    [String]                DAT file
    # @param romdirs    [Array<String>]         ROMs directories
    # @param revert	[Boolean]		Display present ROMs instead
    #
    def check(datfile, romdirs, revert: false)
        io       = @cli.io
        dat      = @cli.dat(datfile)
        storage  = @cli.storage(romdirs)

        missing  = dat.roms - storage.roms
        extra    = storage.roms - dat.roms
        included = dat.roms & storage.roms

        printer  = proc { |entry, subentries|
            io.puts "- #{entry}"
            Array(subentries).each { |entry| io.puts "  . #{entry}" }
        }

        # Warn about presence of headered ROM
        if storage.headered
            warn '===> Headered ROM'
        end


        # Show included ROMs
        if revert
            if included.empty?
                io.puts "==> No rom included"
            else
                io.puts "==> Included roms (#{included.size}):"
                included.dump(comptact: true, &printer)
            end

        # Show mssing and extra ROMs
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

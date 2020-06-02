# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI
    # Check that the ROM directories form an exact match of the DAT file
    #
    # @param datfile    [String]                DAT file
    # @param romdirs    [Array<String>]         ROMs directories
    # @param revert	[Boolean]		Display present ROMs instead
    #
    # @return [self]
    #
    def check(datfile, romdirs, revert: false)
        dat      = make_dat(datfile)
        storage  = make_storage(romdirs)

        missing  = dat.roms - storage.roms
        extra    = storage.roms - dat.roms
        included = dat.roms & storage.roms

        printer  = proc { |entry, subentries|
            @io.puts "- #{entry}"
            Array(subentries).each { |entry| @io.puts "  . #{entry}" }
        }

        # Warn about presence of headered ROM
        if storage.headered
            warn '===> Headered ROM'
        end


        # Show included ROMs
        if revert
            if included.empty?
                @io.puts "==> No rom included"
            else
                @io.puts "==> Included roms (#{included.size}):"
                included.dump(comptact: true, &printer)
            end

        # Show mssing and extra ROMs
        else
            unless missing.empty?
                @io.puts "==> Missing roms (#{missing.size}):"
                missing.dump(compact: true, &printer)
            end
            @io.puts if !missing.empty? && !extra.empty?
            unless extra.empty?
                @io.puts "==> Extra roms (#{extra.size}):"
                extra.dump(compact: true, &printer)
            end
        end

        # Have we a perfect match ?
        if missing.empty? && extra.empty?
            @io.puts '==> PERFECT'
        end

        # Allows chaining
        self
    end


    # -----------------------------------------------------------------


    # Parser for check command
    CheckParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} check [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Check ROMs status, and display missing or extra files.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-r', '--revert', 'Display present files instead'
        opts.separator ''
    end


    # Register check command
    subcommand :check, 'Check ROM status',
               CheckParser do |argv, **opts|
        opts[:romdirs] = argv
        if opts[:dat].nil? && (opts[:romdirs].size >= 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:dat].nil?
            warn "missing datfile"
            exit
        end
        if opts[:romdirs].empty?
            warn "missing ROM directory"
            exit
        end

        [ opts[:dat], opts[:romdirs], revert: opts[:revert] || false ]
    end

end
end

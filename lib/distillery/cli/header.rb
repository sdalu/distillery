# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    # Save ROM header in a specified directory
    #
    # @param hdrdir     [String]                Directory for saving headers
    # @param romdirs    [Array<String>]         ROMs directories
    #
    # @return [self]
    #
    def header(hdrdir, romdirs)
        storage = make_storage(romdirs)
        storage.roms.select(&:headered?).each do |rom|
            file   = File.join(hdrdir, rom.fshash)
            header = rom.header
            if File.exist?(file)
                if header != File.binread(file)
                    warn "different header exists : #{rom.fshash}"
                end
                next
            end
            File.write(file, header)
        end

        self
    end


    # -----------------------------------------------------------------


    # Parser for header command
    HeaderParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} index ROMDIR..."

        opts.separator ""
        opts.separator "Extract ROM embedded header"
        opts.separator ""
        opts.separator "Options:"
        opts.separator ""
    end


    # Register header command
    subcommand :header, 'Extract ROM embedded header',
               HeaderParser do |argv, **opts|
        opts[:romdirs] = ARGV
        if opts[:destdir].nil? && (opts[:romdirs].size == 1)
            opts[:destdir] = File.join(opts[:romdirs].first, '.header')
        end
        if opts[:romdirs].empty?
            warn "missing ROM directory"
            exit
        end

        [ opts[:destdir], opts[:romdirs] ]
    end
end
end

# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Header < Command
    DESCRIPTION = 'Extract embedded header from ROM'

    # Parser for header command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator 'Headers for the following systems are supported:'
        ROM::HEADERS.map { |name:, **| name }.uniq.sort.each do |name|
            opts.separator "  - #{name}"
        end
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ {     rom: "<rom name>",'
        opts.separator '         name: "<destination name>",'
        opts.separator '       ?error: "<error message>" },'
        opts.separator '    ... ]'
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        romdirs   = retrieve_romdirs!  argv
        destdir   = retrieve_destdir! opts[:destdir], romdirs, '.header',
                                      dirname: 'Header'

        header(destdir, romdirs)
    end


    # Save ROM header in a specified directory
    #
    # @param hdrdir     [String]                Directory for saving headers
    # @param romdirs    [Array<String>]         ROMs directories
    #
    def header(hdrdir, romdirs)
        io      = @cli.io
        storage = @cli.storage(romdirs)
        enum    = storage.enum_for(:extract_headers, destdir)

        case @cli.output_mode
        # Text output
        when :text
            enum.each do |rom, copied:, ** |
                if    copied        then io.puts "- #{rom}"
                elsif rom.headered? then io.puts "- #{rom} (copy failed)"
                elsif @cli.verbose  then io.puts "- #{rom} (no header)"
                end
            end

        # Fancy output
        when :fancy
            enum.each do |rom, copied:, **|
                spinner = TTY::Spinner.new("[:spinner] :rom",
                                           :hide_cursor => true,
                                           :output      => io)
                spinner.update(:rom => rom.to_s)
                if    copied        then spinner.success
                elsif rom.headered? then spinner.error('(copy failed)')
                elsif @cli.verbose  then spinner.error('(no header)')
                else                     spinner.reset
                end
            end
            
        # JSON/YAML output
        when :json, :yaml
            data = enum.map { |rom, as:, copied:, **|
                { :rom    => rom.to_s,
                  :error  => if    copied        then nil
                             elsif rom.headered? then 'copy failed'
                             else                     'no header'
                             end,
                  :name   => File.basename(as),
                }.compact
            }
            @cli.write_structured_output(data)

        # That's unexpected
        else
            raise Assert
        end
    end

 end

end
end

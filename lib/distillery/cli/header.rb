# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Header < Command
    DESCRIPTION = 'Extract ROM embedded header'

    # Parser for header command
    Parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Extract embedded header from ROM.'
        opts.separator 'Headers for the following systems are supported:'
        ROM::HEADERS.map { |name:, **| name }.uniq.sort.each do |name|
            opts.separator "  - #{name}"
        end
        opts.separator ''

        opts.separator 'Structured output:'
        opts.separator '  [ {     rom: "<rom name>",'
        opts.separator '         name: "<destination name>",'
        opts.separator '       ?error: "<error message>" },'
        opts.separator '    ... ]'
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        opts[:romdirs] = ARGV
        if opts[:destdir].nil? && (opts[:romdirs].size == 1)
            opts[:destdir] = File.join(opts[:romdirs].first, '.header')
        end
        if opts[:romdirs].empty?
            raise Error, "missing ROM directory"
        end

        header(opts[:destdir], opts[:romdirs])
    end


    # Save ROM header in a specified directory
    #
    # @param hdrdir     [String]                Directory for saving headers
    # @param romdirs    [Array<String>]         ROMs directories
    #
    def header(hdrdir, romdirs)
        io   = @cli.io
        enum = enum_for(:_header, hdrdir, romdirs)

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
            io.puts to_structured_output(data)

        # That's unexpected
        else
            raise Assert
        end
    end


    # @!visibility private
    def _header(hdrdir, romdirs)
        @cli.vault(romdirs)
          .copy(hdrdir, part: :header, force: @force) do |rom, as:, copied:, **|
            yield(rom, as: as, copied: copied)
        end
    end
end

end
end

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
        enum = enum_for(:_header, hdrdir, romdirs)

        case @output_mode
        # Text output
        when :text
            enum.each do |rom, copied:, ** |
                if    copied        then @io.puts "- #{rom}"
                elsif rom.headered? then @io.puts "- #{rom} (copy failed)"
                elsif @verbose      then @io.puts "- #{rom} (no header)"
                end
            end

        # Fancy output
        when :fancy
            enum.each do |rom, copied:, **|
                spinner = TTY::Spinner.new("[:spinner] :rom",
                                           :hide_cursor => true,
                                           :output      => @io)
                spinner.update(:rom => rom.to_s)
                if    copied        then spinner.success
                elsif rom.headered? then spinner.error('(copy failed)')
                elsif @verbose      then spinner.error('(no header)')
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
            @io.puts to_structured_output(data)

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    # @!visibility private
    def _header(hdrdir, romdirs)
        make_storage(romdirs).roms
          .copy(hdrdir, part: :header, force: @force) do |rom, as:, copied:, **|
            yield(rom, as: as, copied: copied)
        end
    end


    # -----------------------------------------------------------------


    # Parser for header command
    HeaderParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} header [options] ROMDIR..."

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

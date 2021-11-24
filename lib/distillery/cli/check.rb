# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI
        
class Check < Command
    DESCRIPTION = 'Check ROM existence according to DAT'
    STATUS      = :okay
    OUTPUT_MODE = [ :text, :yaml, :json ]
    
    SHOW_TYPES  = [ :missing, :extra, :included ]

    # Parser for check command
    Defaults = { :show => [ :missing, :extra ] }
    Parser   = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} check [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION} (display missing or extra files)."
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-s', '--show=TYPES', Array, 
                "Select information to show (#{Defaults[:show].join(',')})",
                " Value: #{SHOW_TYPES.join(', ')}" do |v|
            v.map(&:to_sym).tap {|list|
                if type = list.find {|t| !SHOW_TYPES.include?(t) }
                    raise Error, "Unknown show type (#{type})"
                end
                if list.uniq != list
                    raise Error, "Show types (#{SHOW_TYPES.join(', ')}) can only be specified once"
                end
            }
        end
        opts.on '-I', '--[no-]index[=FILE]', "Index file"
        opts.on '-D', '--dat=FILE',          "DAT file"
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  {  ?missing: [ "<rom name>", ... ],'
        opts.separator '       ?extra: { "<game name>": [ "<rom name>", ... ],'
        opts.separator '                 ... },'
        opts.separator '    ?included: { "<game name>": [ "<rom name>", ... ],'
        opts.separator '                 ... },'
        opts.separator '  }'
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir                " \
                       "# Look for .dat in romdir"
        opts.separator "$ #{PROGNAME} #{self} -s included romdir    " \
                       "# Only display included ROMs"
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
    # @param show	[Array<String>]		Type of ROMs to show
    #
    def check(datfile, source, show = [ :missing, :extra ])
        io      = @cli.io
        dat     = @cli.dat(datfile)
        storage = @cli.storage(source)

        printer = proc { |storage, entries|
            bullet = if storage
                     then io.puts "- #{storage}" ; '  .'
                     else                          '-'
                     end
            Array(entries).each {|entry| io.puts "#{bullet} #{entry}" }
        }

        # Warn about presence of headered ROM
        if storage.headered
            warn '===> Headered ROM'
        end

        # Check ROMs
        data     = show.to_h {|t| [ t, [] ]}
        perfect  = storage.check(dat, **data)

        # Process data
        previous = false
        data.each do |type, list|
            if !list.empty?
                if @cli.structured_output_mode?
                    data[type] =
                        case type
                        when :missing
                            list.flat_map(&:last)
                        when :included, :extra
                            list.to_h.transform_values {|v| v.nil? || v }
                        end
                else
                    io.puts if previous
                    io.puts "==> #{type.capitalize} ROMs (#{list.size}) :"
                    list.each(&printer)
                    previous = true
                end
            end
        end

        if @cli.structured_output_mode?
            @cli.write_structured_output(data)
        elsif perfect
            io.puts if previous
            io.puts '==> PERFECT'
        end
    end

end

end
end

# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Validate < Command
    using Distillery::StringEllipsize

    DESCRIPTION = 'Validate DAT file'
    
    # Parser for validate command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator 'Only ROMs described in DAT file are considered.'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-s', '--summarize',         "Summarize results"
        opts.on '-I', '--[no-]index[=FILE]', "Index file"
        opts.on '-D', '--dat[=FILE]',        "DAT file"
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ { game: "<game name>",'
        opts.separator '      roms: [ {     rom: "<rom name>",'
        opts.separator '                ?error: "<error message>" },'
        opts.separator '              ... ] },'
        opts.separator '    ... ]'
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir"
        opts.separator "$ #{PROGNAME} #{self} -D my/dat -I my/index"
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        romdirs   = retrieve_romdirs!  argv
        datfile   = retrieve_datfile!  opts[:dat    ], romdirs
        indexfile = retrieve_indexfile opts[:index  ], romdirs
        summarize = opts[:summarize]
        
        validate(indexfile || romdirs, datfile, summarize: summarize)
    end


    #
    def validate(source, datfile, summarize: false)
        io         = @cli.io
        dat        = @cli.dat(datfile)
        storage    = @cli.storage(source)

        enum       = storage.enum_for(:validate, dat)
        summarizer = lambda { |count, io|
            io.puts
            io.puts "Not found         : #{count[:not_found        ]}"
            io.puts "Missing duplicate : #{count[:missing_duplicate]}"
            io.puts "Name mismatch     : #{count[:name_mismatch    ]}"
            io.puts "Wrong place       : #{count[:wrong_place      ]}"
        }

        if @cli.output_mode == :fancy
            gspinner, rspinner = nil, nil
            stats              = enum.each do |data|
                width = TTY::Screen.width
                if data.include?(:game) && data.include?(:start)
                    game = data[:game]
                    name = game.name.ellipsize(width - 10, :middle)
                    gspinner = TTY::Spinner::Multi.new("[:spinner] #{name}",
                                                       :hide_cursor => true,
                                                       :output      => io)
                elsif data.include?(:error)
                    case error = data[:error]
                    when String then rspinner.error("-> #{error}")
                    when nil    then rspinner.success
                    else raise Assert
                    end

                elsif data.include?(:rom)
                    rom  = data[:rom]
                    name = rom.name.ellipsize(width - 25, :middle)
                    rspinner = gspinner.register("[:spinner] #{name}")
                    rspinner.auto_spin
                end

            end
            if summarize
                summarizer.call(stats, io)
            end


        elsif (@cli.output_mode == :text) && @cli.verbose
            stats = enum.each do |data|
                if    data.include?(:game) && data.include?(:start)
                    game = data[:game]
                    io.puts "#{game}:"
                elsif data.include?(:rom ) && data.include?(:end  )
                    rom   = data[:rom  ]
                    error = data[:error]
                    case error
                    when String then io.puts " - FAILED: #{rom} -> #{error}"
                    when nil    then io.puts " - OK    : #{rom}"
                    else raise Assert
                    end
                end
            end
            if summarize
                summarizer.call(stats, io)
            end

        elsif @cli.output_mode == :text
            list  = []
            stats = enum.each do |data|
                if   data.include?(:game) && data.include?(:end) &&
                     data[:errors].positive?
                    game = data[:game]
                    io.puts "#{game}"
                    list.each do | rom:, error:, ** |
                        io.puts " - FAILED: #{rom} -> #{error}"
                    end
                    list = []

                elsif data.include?(:rom) && data.include?(:end)
                    list << data if !data[:error].nil?
                end
            end
            if (stats.inject(0) {|o,(k,v)| o += v }).zero?
                io.puts '==> PERFECT'
            end
            
        elsif (@cli.output_mode == :json) || (@cli.output_mode == :yaml)
            games = []
            roms  = []
            stats = enum.each do |data|
                if    data.include?(:rom ) && data.include?(:end  )
                    roms << { :rom     => data[:rom  ].path.entry,
                              :error   => data[:error]
                            }.compact
                elsif data.include?(:game) && data.include?(:end  )
                    games << { :game => data[:game].name,
                               :roms => roms }
                    roms  = []
                end
            end
            io.puts to_structured_output(games)

        # That's unexpected
        else
            raise Assert
        end

    end

end

end
end

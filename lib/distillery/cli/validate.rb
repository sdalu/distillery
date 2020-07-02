# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Validate < Command
    using Distillery::StringEllipsize

    DESCRIPTION = 'Validate ROMs according to DAT file'
    
    # Parser for validate command
    Parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        opts.separator ''
        opts.separator DESCRIPTION
        opts.separator ''

        opts.separator 'Options:'
        opts.on '-s', '--summarize',         "Summarize results"
        opts.on '-I', '--[no-]index[=FILE]', "Index file"
        opts.on '-D', '--dat[=FILE]',        "DAT file"
        opts.separator ''

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
        source = argv

        if source.size == 1
            dirinfo = @cli.dirinfo(source[0], opts)
            opts.merge!(dirinfo)
        end
        if opts[:dat].nil?
            raise Error, "missing DAT file"
        end
        if opts[:index]
            source = opts[:index]
        elsif source.empty?
            raise Error, "missing ROM directory"
        end

        
        validate(source, opts[:dat], summarize: opts[:summarize])
    end


    # Validate ROMs according to DAT/Index file.
    #
    # @param romdirs    [Array<String>]         ROMs directories
    # @param datfile    [String]                DAT file
    #
    def _validate(source, datfile)
        dat     = @cli.dat(datfile)
        vault   = @cli.vault(source)
        stats   = { :not_found     => 0,
                    :name_mismatch => 0,
                    :wrong_place   => 0 }
        checker = lambda { |game, rom|
            m = vault.match(rom)
            if m.nil? || m.empty?
                stats[:not_found] += 1
                'not found'
            elsif (m = m.select {|r| r.name == rom.name }).empty?
                stats[:name_mismatch] += 1
                'name mismatch'
            elsif (m = m.select { |r|
                       store = File.basename(r.path.storage)
                       ROMArchive::EXTENSIONS.any? { |ext|
                           ext = Regexp.escape(ext)
                           store.gsub(/\.#{ext}$/i, '') == game.name
                       } || (store == game.name) || romdirs.include?(store)
                   }).empty?
                stats[:wrong_place] += 1
                'wrong place'
            end
        }

        dat.each_game do |game|
            errors, count = 0, 0
            yield(:game => game, :start => true)
            game.each_rom do |rom|
                yield(:rom => rom, :start => true)
                count  += 1
                errors += 1 if error = checker.call(game,rom)
                yield(:rom => rom, :end => true,
                      :error => error)
            end
            yield(:game => game, :end => true,
                  :errors => errors, :count => count)
        end

        stats
    end
    
    #
    def validate(source, datfile, summarize: false)
        io         = @cli.io
        enum       = enum_for(:_validate, source, datfile)
        summarizer = lambda { |count, io|
            io.puts
            io.puts "Not found     : #{count[:not_found    ]}"
            io.puts "Name mismatch : #{count[:name_mismatch]}"
            io.puts "Wrong place   : #{count[:wrong_place  ]}"
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

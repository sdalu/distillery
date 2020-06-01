# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI
    using Distillery::StringY

    # Validate ROMs according to DAT/Index file.
    #
    # @param romdirs    [Array<String>]         ROMs directories
    # @param datfile    [String]                DAT file
    #
    # @return [self]
    #
    def validate(romdirs, datfile: nil, summarize: false)
        dat        = make_dat(datfile)
        storage    = make_storage(romdirs)
        count      = { :not_found     => 0,
                       :name_mismatch => 0,
                       :wrong_place   => 0 }
        summarizer = lambda { |io|
            io.puts
            io.puts "Not found     : #{count[:not_found    ]}"
            io.puts "Name mismatch : #{count[:name_mismatch]}"
            io.puts "Wrong place   : #{count[:wrong_place  ]}"
        }
        checker    = lambda { |game, rom|
            m = storage.roms.match(rom)

            if m.nil? || m.empty?
                count[:not_found] += 1
                'not found'
            elsif (m = m.select {|r| r.name == rom.name }).empty?
                count[:name_mismatch] += 1
                'name mismatch'
            elsif (m = m.select { |r|
                       store = File.basename(r.path.storage)
                       ROMArchive::EXTENSIONS.any? { |ext|
                           ext = Regexp.escape(ext)
                           store.gsub(/\.#{ext}$/i, '') == game.name
                       } || (store == game.name) || romdirs.include?(store)
                   }).empty?
                count[:wrong_place] += 1
                'wrong place'
            end
        }

        if @output_mode == :fancy
            dat.each_game { |game|
                s_width    = TTY::Screen.width
                r_width    = s_width - 25
                g_width    = s_width - 10

                game_name = game.name.ellipsize(g_width, :middle)
                gspinner = TTY::Spinner::Multi.new("[:spinner] #{game_name}",
                                                   :hide_cursor => true,
                                                   :output      => @io)

                game.each_rom do |rom|
                    rom_name = rom.name.ellipsize(r_width, :middle)
                    rspinner = gspinner.register '[:spinner] :rom'
                    rspinner.update(:rom => rom_name)
                    rspinner.auto_spin

                    case v = checker.call(game, rom)
                    when String then rspinner.error("-> #{v}")
                    when nil    then rspinner.success
                    else raise Assert
                    end
                end
            }
            if summarize
                summarizer.call(@io)
            end


        elsif (@output_mode == :text) && @verbose
            dat.each_game do |game|
                @io.puts "#{game}:"
                game.each_rom do |rom|
                    case v = checker.call(game, rom)
                    when String then @io.puts " - FAILED: #{rom} -> #{v}"
                    when nil    then @io.puts " - OK    : #{rom}"
                    else raise Assert
                    end
                end
            end
            if summarize
                summarizer.call(@io)
            end

        elsif @output_mode == :text
            dat.each_game.flat_map { |game|
                game.each_rom.map { |rom|
                    case v = checker.call(game, rom)
                    when String then [ game.name, rom, v ]
                    when nil    then nil
                    else raise Assert
                    end
                }.compact
            }.compact.group_by { |game,| game }.each { |game, list|
                @io.puts "#{game}"
                list.each { |_, rom, err|
                    @io.puts " - FAILED: #{rom} -> #{err}"
                }
            }

        elsif @output_mode == :json
            @io.puts dat.each_game.map { |game|
                { :game => game.name,
                  :roms => game.each_rom.map { |rom|
                      case v = checker.call(game, rom)
                      when String, nil then [ game.name, rom, v ]
                      else raise Assert
                      end
                      { :rom     => rom.path.entry,
                        :success => v.nil?,
                        :errmsg  => v
                      }.compact
                  }
                }
            }.to_json

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    # -----------------------------------------------------------------


    # Parser for validate command
    ValidateParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} validate [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Validate ROMs according to DAT file'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-s', '--summarize', "Summarize results"
        opts.separator ''
        opts.separator 'JSON output:'
        opts.separator '  [ { game: "<game name>",'
        opts.separator '      roms: [ {     rom: "<rom name>",'
        opts.separator '                success: <true,false>, '
        opts.separator '                 errmsg: "<error message>" },'
        opts.separator '              ... ] },'
        opts.separator '    ... ]'
        opts.separator ''
    end


    # Register validate command
    subcommand :validate, 'Validate ROMs according to DAT file',
               ValidateParser do |argv, **opts|
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

        [ opts[:romdirs], datfile: opts[:dat] ]
    end

end
end

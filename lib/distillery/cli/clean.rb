# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Clean < Command

    DESCRIPTION = 'Remove content not referenced in DAT file'

    # Parser for clean command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} clean [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        romdirs   = retrieve_romdirs!  argv
        datfile   = retrieve_datfile!  opts[:dat    ], romdirs
        indexfile = retrieve_indexfile opts[:index  ], romdirs
        destdir   = retrieve_destdir!  opts[:destdir], romdirs, '.trash',
                                       dirname: 'Removed ROMs'
        
        clean(datfile, indexfile || romdirs, savedir: destdir)
    end


    def clean(datfile, romdirs, savedir: nil)
        enum = enum_for(:_clean, datfile, romdirs, savedir: savedir)

        case @output_mode
        # Text/Fancy output
        when :text, :fancy
            enum.each do |rom, moved:, error: nil |
                moved ||= '<deleted>'
                error   = " (#{error})" if error
                @io.puts "- #{rom} -> #{moved}#{error}"
            end

        # JSON/YAML output
        when :json, :yaml
            # @io.puts to_structured_output(Hash[enum.to_a])

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    private

    
    def _clean(datfile, romdirs, savedir: nil)
        dat        = make_dat(datfile)
        storage    = make_storage(romdirs)
        extra      = storage.roms - dat.roms

        if savedir
            extra.copy(savedir) do |rom, copied:, as:|
                error = if copied
                            rom.delete!
                            nil
                        elsif File.exists?(as)
                            'file exist'
                        else
                            'failed'
                        end
                yield(rom, moved: as, error: error)
            end
        else
            extra.each do |rom|
                rom.delete!
                yield(rom, moved: nil, error: nil)
            end
        end
        
    end

    
end
end

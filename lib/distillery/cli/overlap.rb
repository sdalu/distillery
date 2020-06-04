# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    def overlap(index, romdirs)
        index   = Hash[File.readlines(index).map { |line| line.split(' ', 2) }]
        storage = make_storage(romdirs)
        storage.roms.select { |rom| index.include?(rom.sha1) }
                    .each   { |rom|
            @io.puts rom.path
        }
    end


    # -----------------------------------------------------------------

    # Parser for overlap command
    OverlapParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} overlap [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Check ROMs status according to index file.'
        opts.separator ' and display missing or extra files.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-r', '--revert', "Display present files instead"
        opts.separator ''
    end


    # Register overlap command
    subcommand :overlap, 'Check for overlaping ROM' do |argv, **opts|
        opts[:romdirs] = argv

        [ opts[:index], opts[:romdirs] ]
    end
end
end

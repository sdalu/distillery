# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    def rename(datfile, romdirs)
        dat     = Distillery::DatFile.new(datfile)
        storage = create_storage(romdirs)

        storage.rename(dat)
    end

    # -----------------------------------------------------------------


    # Register rename command
    subcommand :rename, 'Rename ROMs according to DAT' do |argv, **opts|
        opts[:romdirs] = argv
        if opts[:dat].nil? && (opts[:romdirs].size == 1)
            opts[:dat] = File.join(opts[:romdirs].first, '.dat')
        end
        if opts[:dat].nil?
            warn 'missing datfile'
            exit
        end
        if opts[:romdirs].empty?
            warn 'missing ROM directory'
            exit
        end

        [ opts[:dat], opts[:romdirs] ]
    end
end
end

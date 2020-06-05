# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    # Print index (hash and path of each ROM)
    #
    # @param romdirs   [Array<String>]  ROMs directories
    # @param pathstrip [Integer,nil]    Strip path from the first directories
    #
    # @return [self]
    #
    def index(romdirs, pathstrip: nil)

        case @output_mode
        # Text/Fancy output
        when :text, :fancy
            raise "only yaml or json mode are supported"

        # JSON/YAML output
        when :json, :yaml
            make_storage(romdirs).roms.save(@io,
                           type: @output_mode,
                      pathstrip: pathstrip,
                        skipped: ->(path) { warn "SKIPPED: #{path}" } )

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    # -----------------------------------------------------------------


    # Parser for index command
    IndexParser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} index [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator 'Generate index (filename and metadata).'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-p', '--path-strip=INTEGER', Integer,
                "Pathname strip count"
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ {    sha256: "<hexstring>",'                \
                       '           sha1: "<hexstring>",'
        opts.separator '            md5: "<hexstring>",'                \
                       '          crc32: "<hexstring>",'
        opts.separator '           size: <integer>,    '                \
                       '        ?offset: <integer>,'
        opts.separator '      timestamp: "<timestamp>" }'
        opts.separator '    ... ]'
        opts.separator ''
    end


    # Register index command
    subcommand :index, 'Generate hash index',
               IndexParser do |argv, **opts|
        if argv.empty?
            warn "At least one rom directory is required"
            exit
        end

        [ argv, pathstrip: opts[:'path-strip'] ]
    end

end
end

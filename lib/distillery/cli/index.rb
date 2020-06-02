# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

    # Print index (hash and path of each ROM)
    #
    # @param romdirs    [Array<String>]         ROMs directories
    # @param type       [Symbol,nil]            type of checksum to use
    # @param separator  [String]		archive entry separator
    #
    # @return [self]
    #
    def index(romdirs, type: nil, separator: nil)
        enum = enum_for(:_index, romdirs, type: type, separator: separator)

        case @output_mode
        # Text/Fancy output
        when :text, :fancy
            enum.each do |hash, path|
                @io.puts "#{hash} #{path}"
            end

        # JSON output
        when :json
            @io.puts Hash[enum.to_a].to_json

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    def _index(romdirs, type: nil, separator: nil)
        make_storage(romdirs).index(type, separator).each do |hash, path|
            yield(hash, path)
        end
    end


    # -----------------------------------------------------------------


    # Parser for index command
    IndexParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} index [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Generate hash index.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-c', '--cksum=CHECKSUM', ROM::CHECKSUMS,
                "Checksum used for indexing (#{ROM::FS_CHECKSUM})",
                " Value: #{ROM::CHECKSUMS.join(', ')}"
        opts.on '-s', '--separator=CHAR', String,
                "Separator for archive entry (#{ROM::Path::Archive.separator})"
        opts.separator ''
    end


    # Register index command
    subcommand :index, 'Generate hash index',
               IndexParser do |argv, **opts|
        if argv.empty?
            warn "At least one rom directory is required"
            exit
        end

        [ argv, type: opts[:cksum], separator: opts[:separator] ]
    end

end
end

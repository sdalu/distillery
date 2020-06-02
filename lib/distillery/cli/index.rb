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
        enum = enum_for(:_index, romdirs, separator: separator)

        case @output_mode
        # Text/Fancy output
        when :text, :fancy
            type ||= ROM::FS_CHECKSUM
            enum.each do |path, **data|
                @io.puts "#{data[type]} #{path}"
            end

        # JSON/YAML output
        when :json, :yaml
            @io.puts to_structured_output(Hash[enum.to_a])

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    # @!visibility private
    def _index(romdirs, separator: nil)
        make_storage(romdirs).index(separator).each do |path, **data|
            yield(path, **data)
        end
    end


    # -----------------------------------------------------------------


    # Parser for index command
    IndexParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{PROGNAME} index [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Generate index (filename and metadata).'
        opts.separator 'In structured mode all metadata is outputted, but ' \
                       'in text mode'
        opts.separator 'only the selected checksum is present.'
        opts.separator 'Note: checksums are not computed on header part.'
        opts.separator ''
        opts.separator 'Options:'
        opts.on '-c', '--cksum=CHECKSUM', ROM::CHECKSUMS,
                "Checksum used for indexing (#{ROM::FS_CHECKSUM})",
                " Value: #{ROM::CHECKSUMS.join(', ')}"
        opts.on '-S', '--separator=CHAR', String,
                "Separator for archive entry (#{ROM::Path::Archive.separator})"
        opts.separator ''
        opts.separator 'Structured output:'
        opts.separator '  [ { sha256: "<hexstring>",' '        sha1: "<hexstring>",'
        opts.separator '         md5: "<hexstring>",' '       crc32: "<hexstring>",'
        opts.separator '        size: <size>,       ' '    headered: <true,false> }'
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

        [ argv, type: opts[:cksum], separator: opts[:separator] ]
    end

end
end

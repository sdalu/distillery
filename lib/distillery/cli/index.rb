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
    def index(romdirs, type: nil, separator: nil, pathstrip: nil)
        enum = enum_for(:_index, romdirs,
                        separator: separator, pathstrip: pathstrip)

        case @output_mode
        # Text/Fancy output
        when :text, :fancy
            type ||= ROM::FS_CHECKSUM
            enum.each do |path, **data|
                @io.puts "#{data[type]} #{path}"
            end

        # JSON/YAML output
        when :json, :yaml
            data = enum.map { |file, meta|
                [ file, meta.transform_keys(&:to_s) ] }
            @io.puts to_structured_output(Hash[data])

        # That's unexpected
        else
            raise Assert
        end

        # Allows chaining
        self
    end


    # @!visibility private
    def _index(romdirs, separator: nil, pathstrip: nil)
        make_storage(romdirs).roms.index.each do |path, **data|
            if pathstrip&.positive?
                # Explode path according to file separator
                epath = path.split(File::SEPARATOR)

                # In case of archive separator being the same as
                # file separator we need to reconstruct the 'basename'
                if separator == File::SEPARATOR
                    # Lookup for an archive name
                    if i_archive = epath.find_index { |name|
                           ROMArchive::EXTENSIONS.any? { |ext|
                               name.end_with?(".#{ext}")
                           }
                       }
                        # Reconstruct basename
                        epath[i_archive..-1] =
                            epath[i_archive..-1].join(File::SEPARATOR)
                    end
                end

                # Strip path
                epath = epath[pathstrip..-1]

                # Sanity check
                if epath.empty?
                    warn "SKIPPED: #{path}"
                    next
                end

                # Create new path
                path = epath.join(File::SEPARATOR)
            end

            yield(path, **data)
        end
    end


    # -----------------------------------------------------------------


    # Parser for index command
    IndexParser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} index [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator 'Generate index (filename and metadata).'
        opts.separator 'In structured mode all metadata is outputted, but ' \
                       'in text mode'
        opts.separator 'only the selected checksum is present.'
        opts.separator 'Note: checksums are not computed on header part.'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-p', '--path-strip=INTEGER', Integer,
                "Pathname strip count"
        opts.on '-c', '--cksum=CHECKSUM', ROM::CHECKSUMS,
                "Checksum used for indexing (#{ROM::FS_CHECKSUM})",
                " Value: #{ROM::CHECKSUMS.join(', ')}"
        opts.on '-S', '--separator=CHAR', String,
                "Separator for archive entry (#{ROM::Path::Archive.separator})"
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ {    sha256: "<hexstring>",'                \
                       '           sha1: "<hexstring>",'
        opts.separator '            md5: "<hexstring>",'                \
                       '          crc32: "<hexstring>",'
        opts.separator '           size: <size>,       '                \
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

        [ argv, type: opts[:cksum], separator: opts[:separator],
          pathstrip: opts[:'path-strip'] ]
    end

end
end

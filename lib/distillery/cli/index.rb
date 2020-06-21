# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Index < Command
    DESCRIPTION = 'Generate vault index'
    OUTPUT_MODE = [ :yaml, :json ]

    # Parser for index command
    Parser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION} (filename and metadata)."
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-p', '--path-strip=INTEGER', Integer,
                "Pathname strip count" do |v|
            raise Error, "path-strip value must be >= 0" if v.negative?
            v
        end
        opts.on '-i', '--index=[name]',
                "Generate index file in first (.index)" do |v|
            if v&.include?(File::SEPARATOR)
                raise Error, "index file name should contain no base directory"
            end
            v
        end
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ {    sha256: "<hexstring>",'                \
                       '           sha1: "<hexstring>",'
        opts.separator '            md5: "<hexstring>",'                \
                       '          crc32: "<hexstring>",'
        opts.separator '           size: <integer>,    '                \
                       '        ?offset: <integer>,'
        opts.separator '      timestamp: "<timestamp>"'
        opts.separator '    }, ... ]'
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} -i -p1 romdir"
        opts.separator "$ #{PROGNAME} -o index.yaml #{self} -p1 romdir"
        opts.separator ''
    end


    # (see Command#run)
    def run(argv, **opts)
        if argv.empty?
            raise Error, "at least one rom-directory is required"
        end

        # Check for provided index file name
        file = if opts.include?(:index)                       
                   File.join(argv[0], opts[:index] || '.index')
               end

        # Sanity check
        if file
            if !argv.one?
                raise Error, "exactly 1 rom-directory is supported" \
                             " with option --index"
            end
            
            if @cli.verbose
                warn "using #{file} as index file"
            end

            if File.exists?(file) && !@cli.force
                raise Error, "file #{file} exists (use --force)"
            end
        end

        # Do the job
        index(argv, file: file, pathstrip: opts[:'path-strip'])
    end

    
    # Print vault index (hash and path of each ROM)
    #
    # @param romdirs   [Array<String>]  ROMs directories
    # @param pathstrip [Integer,nil]    Strip path from the first directories
    #
    def index(romdirs, file: nil, pathstrip: nil)
        case @cli.output_mode
        # JSON/YAML output
        when :json, :yaml
            @cli.vault(romdirs).save(file || @cli.io,
                           type: @cli.output_mode,
                      pathstrip: pathstrip,
                        skipped: ->(path) { warn "SKIPPED: #{path}" } )
        # Unexpected output mode
        else
            raise Assert
        end
    end

end

end
end

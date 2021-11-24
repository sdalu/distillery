# coding: utf-8
# SPDX-License-Identifier: EUPL-1.2

module Distillery
class CLI

class Repack < Command
    using Distillery::StringEllipsize

    DESCRIPTION = 'Repack archives to the specified format'
    STATUS      = :okay

    # Parser for repack command
    Parser = OptionParser.new do |opts|
        types = ROMArchive::EXTENSIONS.to_a

        # Usage
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR|FILE..."

        # Description
        opts.separator ''
        opts.separator "#{DESCRIPTION}."
        opts.separator 'If another archive is in the way the '		\
                       'operation won\'t be carried out.'
        opts.separator ''

        # Options
        opts.separator 'Options:'
        opts.on '-n', '--dry-run', 'Perform a trial run with no changes made'
        opts.on '-d', '--depth',   'Limit depth of directory scanning'
        opts.on '-F', '--format=FORMAT', types,
                "Select archive format (default: #{ROMArchive::PREFERED})",
                " Possible values: #{types.join(', ')}"
        opts.on       '--filter=FILTER_RULES',
                      'Filter repack candidates (first match)' do |rules|
            # Parse rules
            rules =
                rules.scan(/\G([+-])?((?:[^\,]|\\[^,])*)(?:,|\z)/)
                     .reject {|op, filter| op.nil? && filter.empty? }
                     .map    {|op, filter| [ op, filter.gsub(/\\(.)/, '\1') ] }
            # Check for resulting empty rule set
            if rules.empty?
                raise Error, 'empty rules not allowed in --filter'
            end

            # Find default rule and cut tail
            if dflt_idx = rules.find_index { |op, filter| filter.empty? }
                rules = rules[0..dflt_idx]

            # Otherwise add default rule
            else
                # Opposite action if all the same
                ops = rules.map {|op, filter| op }.uniq
                if ops.one?
                    op = case ops.first
                         when '+' then '-'
                         when '-' then '+'
                         end
                    rules.push [ op,  '' ]
                # Otherwise reject
                else
                    rules.push [ '-', '' ]
                end
            end
            # Return rules
            rules
        end
        opts.separator ''

        # Filter rule
        opts.separator 'Filter rule:'
        opts.separator '  Rules are glob-based comma-separated, '            \
                         'the action accept(+) or reject(-)'
        opts.separator '  is prefix to the glob. The accept prefix '         \
                         'can be omitted.'
        opts.separator '  A default action will be added if not specified. ' \
                         'If all rules are reject'
        opts.separator '  will default to accept(+) otherwise to reject(-).'
        opts.separator ''

        # Structured output
        opts.separator 'Structured output:'
        opts.separator '  [ { file: "<file>", ?error: "<error message>" },'
        opts.separator '    ... ]'
        opts.separator ''

        # Examples
        opts.separator 'Examples:'
        opts.separator "$ #{PROGNAME} #{self} romdir"
        opts.separator "$ #{PROGNAME} #{self} -F zip romdir foo/bar.7z"
        opts.separator "$ #{PROGNAME} #{self} --filter=\'*.zip\' romdir"
        opts.separator "$ #{PROGNAME} #{self} --filter=\'*.zip,+foo/*.7z,-\' romdir"
        opts.separator ''
    end

    
    # (see Command#run)
    def run(argv, **opts)
        repack(argv, opts[:format], filters: opts[:filter   ],
                                      depth: opts[:depth    ],
                                     dryrun: opts[:'dry-run'])
    end

        
    # Repack archives.
    #
    # @param source     [Array<String>]         ROMs directories or files
    # @param type       [String,nil]            Archive type
    # @param filters    [Array]                 Filter each entry
    # @param depth      [Integer,nil]           Limit directory scanning depth
    # @param dryrun     [Boolean]		Perform trial run
    #
    def repack(source, type = nil, filters: nil, depth: nil, dryrun: false)
        type ||= ROMArchive::PREFERED
        io     = @cli.io
        enum   = enum_for(:_repack, source, type,
                          filters: filters, depth: depth, dryrun: dryrun)

        case @cli.output_mode
        # Fancy mode
        when :fancy
            spinner = nil
            enum.each do |file, errmsg = nil, notify: |
                case notify
                when :start
                    spinner = TTY::Spinner.new('[:spinner] :file',
                                               :hide_cursor => true,
                                               :output      => io)
                    width = TTY::Screen.width - (9 + type.size)
                    spinner.update(:file => file.ellipsize(width, :middle))
                    spinner.auto_spin
                when :end
                    if errmsg
                        spinner.error("(#{errmsg})")
                    elsif @cli.verbose
                        spinner.success("-> #{type}")
                    else
                        spinner.clear_line
                    end
                end
            end
            
        # Text mode
        when :text
            enum.each do |file, errmsg = nil, notify: |
                next unless notify == :end
                case errmsg
                when String
                    io.puts "FAILED: #{file} (#{errmsg})"
                else
                    io.puts "OK    : #{file} -> #{type}" if @cli.verbose
                end
            end
            
        # YAML/JSON mode
        when :yaml, :json
            data = enum.select { |file, errmsg = nil, notify: | notify == :end }
                       .map    { |file, errmsg = nil, **|
                                  { :file   => file,
                                    :error  => errmsg }.compact
                               }
            @cli.write_structured_output(data)

        # That's unexpected
        else
            raise Assert
        end
    end

    
    private

    
    # Repack archives
    #
    # @param source     [Array<String>]         ROMs directories or files
    # @param type       [String]                Archive type
    # @param filters    [Array]                 Filter each entry
    # @param depth      [Integer,nil]           Limit directory scanning depth
    # @param dryrun     [Boolean]		Perform trial run
    #
    # @return [Integer] number of repacked archives
    #
    def _repack(source, type, filters: nil, depth: nil, dryrun: false)
        repacked = 0
        @cli.from_romdirs_or_files(source, depth: depth) do |file, dir: '.'|
            # Source
            src = File.join(dir, file)

            # Filtering
            if filters
                m = filters.find { |op, filter|
                    filter.empty? || File.fnmatch?(filter, src)
                }
                next if m.nil? || m[0] == '-'
            end
            
            # Silently ignore if unable to process this file
            #   Either it is an archive format we don't know 
            #   or it is a plain file.
            next unless Archiver.for_file(src)
            
            # Notify of start
            yield(file, notify: :start)

            # Perform repack and notify with result
            begin
                errmsg = if !Archiver.repack(src, type, dryrun: dryrun)
                             "failed"
                         end
                yield(file, errmsg, notify: :end)
                repacked +=1 if errmsg.nil?
            rescue ArchiverNotFound
                # Shouldn't happen as we have checked the source file
                # and only supported type (aka format) should be allowed
                # by the command line
                raise Assert
            rescue Errno::EEXIST
                yield(file, "#{type} exists", notify: :end)
            end
        end
        repacked
    end
    
    
end
                                  
end
end

# coding: utf-8
# SPDX-License-Identifier: EUPL-1.2

require 'securerandom'

module Distillery
class CLI

class Repack < Command
    using Distillery::StringEllipsize

    DESCRIPTION = 'Recompress archives'

    # Parser for repack command
    Parser = OptionParser.new do |opts|
        types = ROMArchive::EXTENSIONS.to_a
        opts.banner = "Usage: #{PROGNAME} #{self} [options] ROMDIR..."

        opts.separator ''
        opts.separator 'Repack archives to the specified format.'
        opts.separator 'If another archive is in the way the '		\
                       'operation won\'t be carried out.'
        opts.separator ''

        opts.separator 'Options:'
        opts.on '-F', '--format=FORMAT', types,
                "Archive format (#{ROMArchive::PREFERED})",
                " Value: #{types.join(', ')}"
        opts.separator ''

        opts.separator 'Structured output:'
        opts.separator '  [ { file: "<file>", ?error: "<error message>" },'
        opts.separator '    ... ]'
        opts.separator ''
    end

    
    # (see Command#run)
    def run(argv, **opts)
        repack(argv, opts[:format])
    end

    
    # Repack archives.
    #
    # @param romdirs    [Array<String>]         ROMs directories
    # @param type       [String]                Archive type
    #
    def repack(romdirs, type = nil)
        # Select archive type if not specified
        type      ||= ROMArchive::PREFERED

        # Build support for the various output mode
        accumulator = []
        decorator   =
            # Fancy mode
            if @output_mode == :fancy
                lambda { |file, type, &block|
                    spinner = TTY::Spinner.new('[:spinner] :file',
                                               :hide_cursor => true,
                                               :output      => @io)
                    width = TTY::Screen.width - (8 + type.size)
                    spinner.update(:file => file.ellipsize(width, :middle))
                    spinner.auto_spin
                    case errmsg = block.call
                    when String then spinner.error("(#{errmsg})")
                    else             spinner.success("-> #{type}")
                    end
                }
            # Text mode
            elsif @output_mode == :text
                lambda { |file, type, &block|
                    case errmsg = block.call
                    when String
                        @io.puts "FAILED: #{file} (#{errmsg})"
                    else
                        @io.puts "OK    : #{file} -> #{type}" if @verbose
                    end
                }
            # JSON mode
            elsif @output_mode == :json
                lambda { |file, type, &block|
                    errmsg = block.call
                    accumulator << { :file   => file,
                                     :error  => errmsg,
                                   }.compact
                }
            # That's unexpected
            else
                raise Assert
            end
        finalizer   =
            if (@output_mode == :json) || (@output_mode == :yaml)
                lambda {
                    @io.puts to_structured_output(accumulator)
                }
            end

        # Perform re-packing
        from_romdirs(romdirs) do |srcfile, dir:|
            # Destination file according to archive type
            dstfile  = srcfile.dup
            dstfile += ".#{type}" unless dstfile.sub!(/\.[^.\/]*$/, ".#{type}")

            # Path for src and dst
            src      = File.join(dir, srcfile)
            dst      = File.join(dir, dstfile)

            # If source and destination are the same
            #  - move source out of the way as we could recompress
            #    using another algorithm
            if srcfile == dstfile
                phyfile = srcfile + '.' + SecureRandom.alphanumeric(10)
                phy     = File.join(dir, phyfile)
                File.rename(src, phy)
            else
                phyfile = srcfile
                phy     = src
            end

            # Re-compress
            decorator.call(srcfile, type) {
                next "#{type} exists" if File.exist?(dst)
                archive = Distillery::Archiver.for(dst)
                Distillery::Archiver.for(phy).each do |entry, i|
                    archive.writer(entry) do |o|
                        while data = i.read(32 * 1024)
                            o.write(data)
                        end
                    end
                end
                File.unlink(phy)
            }
        end

        # Apply finalizer if required (for json)
        finalizer&.call()
    end


end
                                  
end
end

# coding: utf-8
# SPDX-License-Identifier: EUPL-1.2

require 'securerandom'

module Distillery
class CLI
    using Distillery::StringY

    def repack(romdirs, type = nil)
        type    ||= ROMArchive::PREFERED

        decorator =
            if @output_mode == :fancy
                lambda {|file, type, &block|
                    spinner = TTY::Spinner.new('[:spinner] :file',
                                               :hide_cursor => true,
                                               :output      => @io)
                    width = TTY::Screen.width - 8
                    spinner.update(:file => file.ellipsize(width, :middle))
                    spinner.auto_spin
                    case v = block.call
                    when String then spinner.error("(#{v})")
                    else             spinner.success("-> #{type}")
                    end
                }

            elsif @output_mode == :text
                lambda {|file, type, &block|
                    case v = block.call
                    when String
                        @io.puts "FAILED: #{file} (#{v})"
                        @io.puts "OK    : #{file} -> #{type}" if @verbose
                    end
                }

            else

                raise Assert
            end


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

            # Recompress
            decorator.(srcfile, type) {
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
    end


    # -----------------------------------------------------------------


    # Parser for repack command
    RepackParser = OptionParser.new do |opts|
        types = ROMArchive::EXTENSIONS.to_a
        opts.banner = "Usage: #{PROGNAME} repack [options] ROMDIR..."

        opts.separator ""
        opts.separator "Repack archives to the specified format"
        opts.separator ""
        opts.separator "NOTE: if an archive in the new format already exists the operation"
        
        opts.separator "      won't be carried out" 
        opts.separator ""
        opts.separator "Options:"
        opts.on '-F', '--format=FORMAT', types,
                "Archive format (#{ROMArchive::PREFERED})",
                " Value: #{types.join(', ')}"
        opts.separator ""
    end


    # Register repack command
    subcommand :repack, 'Recompress archives',
               RepackParser do |argv, **opts|
        opts[:romdirs] = argv

        [ opts[:romdirs], opts[:format] ]
    end

end
end

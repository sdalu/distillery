# SPDX-License-Identifier: EUPL-1.2

require 'open3'
require 'yaml'

module Distillery
class Archiver

# Use external program to process archive
# Selection of external program is described in external.yaml
#
class External < Archiver
    Archiver.add self

    # Perform registration of the various archive format
    # supported by this archiver provider
    #
    # @param list         [Array<String>]	list of format to register
    # @param default_file [String]		default configuration file
    #
    # @return [void]
    #
    def self.registering(list         = [ '7z', 'zip' ],
                         default_file = File.join(__dir__, 'external.yaml'))
        dflt_config = YAML.load_file(default_file)

        if Array === list
            list = Hash[list.map {|app| [ app, {} ] }]
        end

        list.each {|app, cfg|
            dflt       = dflt_config.dig(app) || {}
            extensions = Array(cfg.dig('extension')  || dflt.dig('extension'))
            mimetypes  = Array(cfg.dig('mimetype' )  || dflt.dig('mimetype' ))
            list       = {
                :cmd    => cfg .dig('list', 'cmd')   || cfg .dig('cmd') ||
                           dflt.dig('list', 'cmd')   || dflt.dig('cmd'),
                :args   => cfg .dig('list', 'args')  ||
                           dflt.dig('list', 'args'),
                :parser => if parser = (cfg .dig('list', 'parser')      ||
                                        dflt.dig('list', 'parser'))
                               Regexp.new('\A' + parser + '\Z')
                           end,
                :validator => cfg .dig('list', 'validator') ||
                              dflt.dig('list', 'validator')
            }
            read       = {
                :cmd    => cfg .dig('read', 'cmd')   || cfg .dig('cmd') ||
                           dflt.dig('read', 'cmd')   || dflt.dig('cmd'),
                :args   => cfg .dig('read', 'args')  ||
                           dflt.dig('read', 'args'),
            }
            write      = {
                :cmd    => cfg .dig('write', 'cmd')  || cfg .dig('cmd') ||
                           dflt.dig('write', 'cmd')  || dflt.dig('cmd'),
                :args   => cfg .dig('write', 'args') ||
                           dflt.dig('write', 'args'),
            }
            delete     = {
                :cmd    => cfg .dig('delete', 'cmd')  || cfg .dig('cmd') ||
                           dflt.dig('delete', 'cmd')  || dflt.dig('cmd'),
                :args   => cfg .dig('delete', 'args') ||
                           dflt.dig('delete', 'args'),
            }

            if list[:cmd].nil? || read[:cmd].nil?
                Archiver.logger&.warn {
                    "#{self}: command not defined for #{app} program (SKIP)"
                }
                next
            end
            if write[:cmd].nil?
                Archiver.logger&.warn {
                    "#{self}: write mode not supported for #{app} program"
                }
            end
                
            Archiver.register(External.new(list, read, write, delete,
                                           extensions: extensions,
                                            mimetypes: mimetypes))
        }
    end
    
    def initialize(list, read, write=nil, delete=nil,
                   extensions:, mimetypes: nil)
        @list       = list
        @read       = read
        @write      = write
        @delete     = delete
        @extensions = extensions
        @mimetypes  = mimetypes
    end
    
                
    # (see Archiver#extensions)
    def extensions
        @extensions
    end

    
    # (see Archiver#mimetypes)
    def mimetypes
        @mimetypes
    end

    # (see Archiver#each)
    def each(file, &block)
        return to_enum(:each, file) if block.nil?
        entries(file).each {|entry|
            reader(file, entry) {|io|
                block.call(entry, io)
            }
        }
    end

    # (see Archiver#reader)
    def reader(file, entry, &block)
        subst = { '$(infile)' => file, '$(entry)' => entry  }
        cmd   = @read[:cmd ]
        args  = @read[:args].map{|e| e.gsub(/\$\(\w+\)/, subst) }

        Open3.popen2(cmd, *args) {|stdin, stdout|
            stdin.close_write
            block.call(InputStream.new(stdout))
        }
    end

    # (see Archiver#writer)
    def writer(file, entry, &block)
        subst = { '$(infile)' => file, '$(entry)' => entry  }
        cmd   = @write[:cmd ]
        args  = @write[:args].map{|e| e.gsub(/\$\(\w+\)/, subst) }

        Open3.popen2(cmd, *args) {|stdin, stdout|
            block.call(OutputStream.new(stdin))
        }
    end

    # (see Archiver#delete!)
    def delete!(file, entry)
        subst = { '$(infile)' => file, '$(entry)' => entry  }
        cmd   = @delete[:cmd ]
        args  = @delete[:args].map{|e| e.gsub(/\$\(\w+\)/, subst) }

        Open3.popen2(cmd, *args) {|stdin, stdout|
            stdin.close_write
        }

        true
    end

    # (see Archiver#entries)
    def entries(file)
        subst     = { '$(infile)' => file }
        cmd       = @list[:cmd      ]
        args      = @list[:args     ].map{|e| e.gsub(/\$\(\w+\)/, subst) }
        parser    = @list[:parser   ]
        validator = @list[:validator]
        
        stdout, stderr, status = Open3.capture3(cmd, *args)

        if ! status.exitstatus.zero?
            raise ExecError, "running external command failed (#{stderr})"
        end

        stdout.force_encoding('BINARY').lines(chomp: true).map {|l|
            unless m = l.match(parser)
                raise ProcessingError, "unable to parse entry (#{file}) (#{l})"
            end

            if validator && validator.find {|k,v| m[k] != v }
                next
            end

            m[:entry]
        }.compact
    end
end

end
end


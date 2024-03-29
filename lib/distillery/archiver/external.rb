# SPDX-License-Identifier: EUPL-1.2

require 'open3'
require 'yaml'

module Distillery
class Archiver

# Use external program to process archive
# Selection of external program is described in external.yaml
#
class External < Archiver
    module ArgumentSubstitution
        refine String do
            def with_arguments(args)
                # Normalize keys
                subst = args.transform_keys {|k| k.to_s }

                # Derive new keys (special escaping)
                zip_entry_escape = ->(s) { s.gsub(/[\\\[\]]/, '\\\\\0') }
                if s = subst['entry']
                    subst['entry:zip'] = zip_entry_escape.(s)
                end
                if s = subst['new_entry']
                    subst['new_entry:zip'] = zip_entry_escape.(s)
                end

                # Perform substitution
                subst.transform_keys! {|k| "$(#{k})" }
                self.gsub(/\$\(\w+(?::\w+)?\)/, subst)
            end
        end
    end
    using ArgumentSubstitution

    # Adding ourselves to the Archiver list
    Archiver.add self

    # Perform registration of the various archive format
    # supported by this archiver provider
    #
    # @param list         [Array<String>]       list of format to register
    # @param default_file [String]              default configuration file
    #
    # @return [void]
    #
    def self.registering(list         = [ '7z', 'zip' ],
                         default_file = File.join(__dir__, 'external.yaml'))
        dflt_config = YAML.load_file(default_file)

        if list.is_a?(Array)
            list = Hash[list.map { |app| [ app, {} ] }]
        end

        list.each do |app, cfg|
            dflt       = dflt_config.dig(app) || {}
            extensions = Array(cfg.dig('extension') || dflt.dig('extension'))
            mimetypes  = Array(cfg.dig('mimetype' ) || dflt.dig('mimetype' ))
            list       = {
                :cmd    => cfg .dig('list', 'cmd')    || cfg .dig('cmd') ||
                           dflt.dig('list', 'cmd')    || dflt.dig('cmd'),
                :args   => cfg .dig('list', 'args')   ||
                           dflt.dig('list', 'args'),
                :parser => if parser = (cfg .dig('list', 'parser')      ||
                                        dflt.dig('list', 'parser'))
                               Regexp.new('\A' + parser + '\Z')
                           end,
                :validator => cfg .dig('list', 'validator') ||
                              dflt.dig('list', 'validator')
            }
            read       = {
                :cmd    => cfg .dig('read', 'cmd')    || cfg .dig('cmd') ||
                           dflt.dig('read', 'cmd')    || dflt.dig('cmd'),
                :args   => cfg .dig('read', 'args')   ||
                           dflt.dig('read', 'args'),
            }
            write      = {
                :cmd    => cfg .dig('write', 'cmd')   || cfg .dig('cmd') ||
                           dflt.dig('write', 'cmd')   || dflt.dig('cmd'),
                :args   => cfg .dig('write', 'args')  ||
                           dflt.dig('write', 'args'),
            }
            delete     = {
                :cmd    => cfg .dig('delete', 'cmd')  || cfg .dig('cmd') ||
                           dflt.dig('delete', 'cmd')  || dflt.dig('cmd'),
                :args   => cfg .dig('delete', 'args') ||
                           dflt.dig('delete', 'args'),
            }
            rename     = {
                :cmd    => cfg .dig('rename', 'cmd')  || cfg .dig('cmd') ||
                           dflt.dig('rename', 'cmd')  || dflt.dig('cmd'),
                :args   => cfg .dig('rename', 'args') ||
                           dflt.dig('rename', 'args'),
            }

            if list[:cmd].nil? || read[:cmd].nil?
                Archiver.logger&.warn do
                    "#{self}: command not defined for #{app} program (SKIP)"
                end
                next
            end
            if write[:cmd].nil?
                Archiver.logger&.warn do
                    "#{self}: write mode not supported for #{app} program"
                end
            end

            Archiver.register(External.new(list, read, write, delete, rename,
                                           extensions: extensions,
                                            mimetypes: mimetypes))
        end
    end


    def initialize(list, read, write = nil, delete = nil, rename = nil,
                   extensions:, mimetypes: nil)
        @list       = list
        @read       = read
        @write      = write
        @delete     = delete
        @rename     = rename
        @extensions = extensions
        @mimetypes  = mimetypes
    end


    # (see Archiver#write_enabled)
    def write_enabled
        ! @write.nil?
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
    def each(file)
        return to_enum(:each, file) unless block_given?

        entries(file).each do |entry|
            reader(file, entry) do |io|
                yield(entry, io)
            end
        end
    end


    # (see Archiver#empty?)
    def empty?(file)
        entries(file).none?
    end

    
    # (see Archiver#include?)
    def include?(file, entry)
        entries(file).any? { |e| e == entry }
    end

    
    # (see Archiver#entries)
    def entries(file)
        # Ensure file exist
        exist!(file)

        # Perform operation
        subst     = { :infile => file }
        cmd       = @list[:cmd      ]
        args      = @list[:args     ]&.map { |e| e.with_arguments(subst) }
        parser    = @list[:parser   ]
        validator = @list[:validator]

        stdout, stderr, status = Open3.capture3(cmd, *args)

        if !status.exitstatus.zero?
            raise ExecError, "running external command failed (#{stderr})"
        end

        stdout.force_encoding('BINARY').lines(chomp: true).map { |l|
            unless (m = l.match(parser))
                raise ProcessingError, "unable to parse entry (#{file}) (#{l})"
            end

            if validator&.find { |k, v| m[k] != v }
                next
            end

            m[:entry]
        }.compact
    end


    # (see Archiver#reader)
    def reader(file, entry)
        # Ensure file exist
        include!(file, entry)

        # Perform operation
        subst = { :infile => file, :entry => entry }
        cmd   = @read[:cmd ]
        args  = @read[:args]&.map { |e| e.with_arguments(subst) }

        Open3.popen2(cmd, *args) do |stdin, stdout|
            stdin.close_write
            yield(InputStream.new(stdout))
        end
    end


    # (see Archiver#writer)
    def writer(file, entry)
        # Sanity check
        raise OperationNotSupported if @write.nil?

        # Perform operation
        subst = { :infile => file, :entry => entry }
        cmd   = @write[:cmd ]
        args  = @write[:args]&.map { |e| e.with_arguments(subst) }

        Open3.popen2(cmd, *args) do |stdin, _stdout|
            yield(OutputStream.new(stdin))
        end
    end


    # (see Archiver#delete!)
    def delete!(file, entry)
        # If no dedicated operation, fallback to emulation
        return super(file, entry) if @delete.nil?

        # Ensure file exist
        exist!(file)
        
        # Perform operation
        subst = { :infile => file, :entry => entry }
        cmd   = @delete[:cmd ]
        args  = @delete[:args]&.map { |e| e.with_arguments(subst) }

        stdout, stderr, status = Open3.capture3(cmd, *args)
        
        # Done
        true
    end


    # (see Archiver#rename)
    def rename(file, entry, new_entry, force: false)
        # If no dedicated operation, fallback to emulation
        return super(file, entry, new_entry, force: force) if @rename.nil?
        
        # Ensure file exist
        exist!(file)

        # Deal with existing new entry
        #  (as we need consistent behaviour between external implementations)
        if include?(file, new_entry)
            # If same, consider it done and remove entry
            if same?(file, entry, new_entry)
                delete!(file, entry)
                return true
            end
            # If force not enabled, stop here
            if !force
                return false
            end
            
            # Ensure existing entry is removed
            delete!(file, new_entry)
        end
        
        # Perform operation
        subst = { :infile    => file,
                  :entry     => entry, :new_entry => new_entry
                }
        cmd   = @rename[:cmd ]
        args  = @rename[:args]&.map { |e| e.with_arguments(subst) }

        stdout, stderr, status = Open3.capture3(cmd, *args)
        
        # Done
        true
    end

end

end
end


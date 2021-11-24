require 'forwardable'

module Distillery
class CLI

class Command
    extend Forwardable
    def_delegators :@cli, :make_storage, :make_dat
    
    def self.cmdname
        if self.const_defined?(:NAME)
            self::NAME
        else
            self.name.split('::')[-1]
                .gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2')
                .gsub(/([a-z\d])([A-Z])/,     '\1-\2')
                .downcase
        end
    end
    
    def self.to_s
        self.cmdname
    end
    
    def initialize(cli)
        @cli = cli
    end

    # Process the command
    #
    # @param argv [Array<String>]		command line arguments
    # @param opts [Hash{Symbol => Object}]	processing options
    #
    def run(argv, **opts)
    end

    
    # Format data according to the selected (structured) output mode
    #
    # @param data 	[Object]	data to format
    #
    # @return [String] formatted data
    #
    def to_structured_output(data)
        case @cli.output_mode
        when :yaml then data.to_yaml
        when :json then data.to_json
        else raise Assert
        end
    end

    protected


    # Retrieve ROM directories
    #
    # @param romdirs [Array<String>]   list of ROM directories
    #
    # @raise [Error] if list is empty
    #
    # @return [Array<String>]   list of ROM directory
    #
    def retrieve_romdirs!(romdirs)
        romdirs.tap {|o|
            raise Error, "ROM directory not specified" if o.empty?
        }
    end


    # Retrieve destination directory
    #
    # @param destdir [String]          destination directory
    # @param romdirs [Array<String>]   list of ROM directories
    # @param subdir  [String]          directory to use inside romdirs
    # @param dirname [String]          directory name
    #
    # @raise [Error] if no directory available
    #
    # @return [String] destination directory
    #
    def retrieve_destdir!(destdir, romdirs = nil, subdir = nil,
                          dirname: 'Destination')
        if destdir
            destdir
        elsif romdir = Array(romdirs).first
            File.join( *[ romdir, subdir ].compact )
        else
            raise Error, "#{dirnanme} directory is missing"
        end
    end


    # Retrieve DAT file
    #
    # @param datfile [String,nil]      DAT file
    # @param romdirs [Array<String>]   list of ROM directories
    #
    # @raise [Error] if DAT file missing or
    #                asking for relative without ROM directory
    #
    # @return [String] DAT file
    #
    def retrieve_datfile!(datfile, romdirs = nil)
        romdir  = Array(romdirs).first

        if datfile.nil?
            if romdir
                File.join(romdir, DAT).then {|f| File.exists?(f) ? f : nil }
            end || (raise Error, "missing DAT file")
        elsif datfile.include?(File::SEPARATOR)
            datfile
        elsif romdir
            File.join(romdir, datfile)
        else
            raise Error, "ROM directory relative DAT file is not supported"
        end
    end

    # Retrieve index file
    #
    # @param datfile [String,nil]      DAT file
    # @param romdirs [Array<String>]   list of ROM directories
    #
    # @return [String] index file
    # @return [nil]    if no index file available
    #
    def retrieve_indexfile(indexfile, romdirs = nil)
        romdir = if Array(romdirs).one?
                     Array(romdirs).first
                 end

        case indexfile
        when false
        when nil, true
            if romdir
                File.join(romdir, INDEX)
                    .then {|f| File.exists?(f) ? f : nil }
            end
        when String
            if indexfile.include?(File::SEPARATOR)
                indexfile
            elsif romdir
                File.join(romdir, indexfile)
            end
        else raise ArgumentError
        end
    end
    
    
end

end
end

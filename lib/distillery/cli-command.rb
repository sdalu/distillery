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
        case @output_mode
        when :yaml then data.to_yaml
        when :json then data.to_json
        else raise Assert
        end
    end
    
end

end
end

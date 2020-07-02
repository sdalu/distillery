# coding: utf-8
# SPDX-License-Identifier: EUPL-1.2

require 'set'
require 'optparse'
require 'json'
require 'yaml'
require 'tty/screen'
require 'tty/logger'
require 'tty/spinner'
require 'tty/spinner/multi'
require 'tty/progressbar'

require_relative 'storage'
require_relative 'datfile'
require_relative 'refinements'
require_relative 'cli-command'


unless defined?(::Version)
    Version = Distillery::VERSION
end


module Distillery

class CLI
    using Distillery::StringEllipsize

    # Command line error reporting 
    class Error < Distillery::Error
    end

    
    # List of output mode
    # @note All the output mode are not necessarily supported
    #       by all the commands
    OUTPUT_MODE = [ :text, :fancy, :json, :yaml ].freeze


    # Global option parser
    #
    GlobalParser = OptionParser.new do |opts|
        # Usage
        opts.banner = "Usage: #{opts.program_name} [options] CMD [opts] [args]"

        # Description
        opts.separator ''

        # Options
        opts.separator 'Informative options:'
        opts.on '-h', '--help',         "Show this message" do
            puts opts
            puts ''
            puts 'Commands:'
            CLI.commands.each { |name, klass|
                puts '    %-12s %s' % [ klass.cmdname, klass::DESCRIPTION ]
            }
            puts ''
            puts "See '#{opts.program_name} CMD --help'"                \
                 " for more information on a specific command"
            puts ''
            exit
        end
        opts.on '-V', '--version',      "Show version" do
            puts opts.ver
            exit
        end        

        # Global options
        opts.separator ''
        opts.separator 'Global options:'
        opts.on '-o', '--output=FILE',                   "Output file"
        opts.on '-m', '--output-mode=MODE', OUTPUT_MODE,
                "Output mode (#{OUTPUT_MODE.first})",
                " Value: #{OUTPUT_MODE.join(', ')}"
        opts.on '-S', '--separator=CHAR', String,
                "Separator for archive entry (#{ROM::Path::Archive.separator})"
        opts.on '-f', '--force',                         "Force operation"
        opts.on '-p', '--[no-]progress',                 "Show progress"
        opts.on '-v', '--[no-]verbose',                  "Run verbosely"
    end


    # Program name
    PROGNAME = GlobalParser.program_name


    # Test if a class is a CLI::Command implementation
    #
    # @param klass [Class]	class to test for command implementation
    #
    # @return [Boolean]
    #
    def self.command_class?(klass)
        klass.instance_of?(Class) && (klass < Command)
    end


    # List of supported commands.
    #
    # @return [Hash{String => Class}]
    #
    def self.commands
        self.constants.lazy 
            .map    {|c| self.const_get(c)     }
            .select {|k| CLI.command_class?(k) }
            .to_h   {|k| [ k.cmdname, k ]      }
    end


    # Find the command class corresponding to the name.
    #
    # @param name [String]	command name
    #
    # @return [Class]		found command class (inherited from Command)
    # @return [nil]		if not found
    #
    def self.find_command_class(name)
        self.commands.find {|n,k| n == name }&.last
    end



    
    # Run the command line
    #
    def self.run(argv = ARGV)
        self.new.parse(argv).run
    rescue OptionParser::InvalidArgument, CLI::Error => e
        warn "#{PROGNAME}: #{e}"
        exit 1
    end




    def initialize
        @output_mode = OUTPUT_MODE.first
        @io          = $stdout
        @force       = false
        @verbose     = true
        @progress    = true

        @argv        = []
        @opts        = {}
        @cmdk        = nil
    end

    attr_reader :output_mode
    attr_reader :io
    attr_reader :force
    attr_reader :verbose
    attr_reader :progress

    
    # Run command line
    #
    # @param argv [Array<String>]	command line arguments
    #
    # @raises OptionParser::InvalidArgument
    # @raises CLI::Error
    #
    def parse(argv)
        # Parsed option holder
        opts = {}

        # Parse global options
        GlobalParser.order!(argv, into: opts)

        # Check for command processor class
        cmdname = argv.shift
        raise Error, "command missing" if cmdname.nil?
        cmdk    = CLI.find_command_class(cmdname)
        raise Error, "command \'#{cmdname}\' is not recognized" if cmdk.nil?

        # Adjust default values
        if cmdk.const_defined?(:OUTPUT_MODE)
            @output_mode = cmdk::OUTPUT_MODE.first
        end
        
        # Process our options
        if opts.include?(:output)
            @io = File.open(opts[:output], File::CREAT|File::TRUNC|File::WRONLY)
        end
        if opts.include?(:verbose)
            @verbose = opts[:verbose]
        end
        if opts.include?(:progress)
            @progress = opts[:progress]
        end
        if opts.include?(:'output-mode')
            @output_mode = opts[:'output-mode']
        end
        if opts.include?(:force)
            @force = opts[:force]
        end
        if opts.include?(:separator)
            ROM::Path::Archive.separator = opts[:separator]
        end
        
        # Downgrade output mode if not a TTY
        if (@output_mode == :fancy) && !@io.tty?
            @output_mode = :text
        end
        if cmdk.const_defined?(:OUTPUT_MODE) &&
           !cmdk::OUTPUT_MODE.include?(@output_mode)
            raise Error, "selected output mode (#{@output_mode}) unavailable" \
                         " for #{cmdk} command"
        end

        # Parse command, and run it
        if cmdk.const_defined?(:Parser)
            cmdk::Parser.order!(argv, into: opts)
        end

        # Save parsing results
        @argv = argv
        @opts = opts
        @cmdk = cmdk
        
        # Chainable
        self
    end

    
    # Run command line
    #
    def run
        return nil if @cmdk.nil?
        @cmdk::new(self).run(@argv, **@opts)
    end
    

    # Get directory metadata files
    #
    # @param dir	[String]	Directory to lookup
    # @param opts	[Hash]		Directory information
    #
    # @return [Hash{Symbol=>[String,nil]}]
    #
    def dirinfo(dir, opts={})
        info = {}
        info[:dat  ] =
            case val = opts[:dat]
            when false     then nil
            when nil, true then File.join(dir, DAT)
                                    .then {|f| File.exists?(f) ? f : nil }
            when String    then val.include?(File::SEPARATOR) \
                                ? val : File.join(dir, val)
            else raise ArgumentError
            end

        info[:index] =
            case val = opts[:index]
            when false     then nil
            when nil, true then File.join(dir, INDEX)
                                    .then {|f| File.exists?(f) ? f : nil }
            when String    then val.include?(File::SEPARATOR) \
                                ? val : File.join(dir, val)
            else raise ArgumentError
            end

        info.compact
    end
    
    # Create DAT from file
    #
    # @param file       [String]        dat file
    # @param verbose    [Boolean]       be verbose
    #
    # @return [DatFile]
    #
    def dat(file, verbose: @verbose, progress: @progress)
        DatFile.from_file(file).tap { |dat|
            $stderr.puts "DAT = #{dat.version}" if verbose
        }
    end


    # Potential ROM from directory.
    # @see Vault.from_dir for details
    #
    # @param romdirs   [Array<String>]  path to rom directoris
    # @param depth     [Integer,nil]    exploration depth
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir: [String,nil]     directory relative to
    #
    def from_romdirs(romdirs, depth: nil, &block)
        romdirs.each do |dir|
            Vault.from_dir(dir, depth: depth, &block)
        end
    end

    
    # Potential ROM from directory or explicitly listed files
    # @see Vault.from_dir for details
    #
    # @param romdirs   [Array<String>]  path to rom directoris
    # @param depth     [Integer,nil]    exploration depth
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir: [String]         directory relative to (optional)
    #
    def from_romdirs_or_files(source, precheck: false, depth: nil, &block)
        if precheck
            source.each do |file|
                if !File.exist?(file)
                    raise "non-existing: #{file}"
                elsif !File.file?(file) && !File.directory?(file)
                    raise "unknown entry type: #{file}"
                end
            end
        end
        
        source.each do |file|
            unless File.exist?(file)
                warn "skipping non-existing: #{file}"
                next
            end

            if File.file?(file)
                yield(file)
            elsif File.directory?(file)
                Vault.from_dir(file, depth: depth, &block)
            else
                warn "skipping unknown entry type: #{file}"
            end
        end
    end

    
    # Create Storage from ROMs directories
    #
    # @param romdirs    [Array<String>] array of ROMs directories
    # @param verbose    [Boolean]       be verbose
    #
    # @return [Storage]
    #
    def storage(romdirs, depth: nil,
                     verbose: @verbose, progress: @progress)
        Storage::new(vault(romdirs, depth: depth, verbose: verbose,
                           progress: progress))
    end


    # Create Vault from ROMs directories
    #
    # @param source     [Array<String>] array of ROMs directories
    # @param source     [String]        index file
    # @param depth      [Integer]       directory depth
    # @param verbose    [Boolean]       be verbose
    # @param progress   [Boolean]       show progress
    #
    # @return [Vault]
    #
    def vault(source, depth: nil, verbose: @verbose, progress: @progress)
        case source
        # Process as Vault index
        when String
            set   = Set.new
            oos   = lambda { |rom| set << rom.path.storage ; true }
            vault = Vault.load(source, out_of_sync: oos)
            if !set.empty?
                warn "index file #{source} is out of sync"
                if verbose
                    set.each do |path|
                        warn "Out of sync: #{path}"
                    end
                end
            end
            
        # Process as ROM directories
        when Array
            vault = Vault::new
            vault_adder = ->(file, dir:) { vault.add_from_file(file, dir) }
            if progress
                TTY::Spinner.new('[:spinner] :file', :hide_cursor => true,
                                                     :clear       => true)
                            .run('Done!') do |spinner|
                    from_romdirs(source, depth: depth) do | file, dir: |
                        width = TTY::Screen.width - 8
                        spinner.update(:file => file.ellipsize(width, :middle))
                        vault_adder.call(file, dir: dir)
                    end
                end
            else
                from_romdirs(source, depth: depth, &vault_adder)
            end

        # Oops
        else
            raise ArgumentError
        end

        # Return vault
        vault
    end

end
end


require_relative 'cli/check'
require_relative 'cli/validate'
require_relative 'cli/index'
# require_relative 'cli/rename'
# require_relative 'cli/rebuild'
require_relative 'cli/repack'
# require_relative 'cli/overlap'
require_relative 'cli/header'
# require_relative 'cli/clean'
# require_relative 'cli/v'

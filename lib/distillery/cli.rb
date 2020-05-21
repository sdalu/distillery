# SPDX-License-Identifier: EUPL-1.2

require 'optparse'
require 'json'
require 'tty/screen'
require 'tty/logger'
require 'tty/spinner'
require 'tty/spinner/multi'
require 'tty/progressbar'

require_relative 'storage'
require_relative 'datfile'
require_relative 'refinements'


if !defined?(::Version)
    Version = Distillery::VERSION 
end


module Distillery

class CLI
    using Distillery::StringY
    
    # List of available output mode
    OUTPUT_MODE = [ :text, :fancy, :json ]

    
    # @!visibility private
    @@subcommands = {}


    # Execute the CLI
    def self.run(argv = ARGV)
        self.new.parse(argv)
    end

    
    # Register a new (sub)command into the CLI
    #
    # @param name [Symbol]
    # @param description [String]
    # @param optpartser [OptionParser]
    #
    # @yieldparam argv [Array<String>]
    # @yieldparam into: [Object]
    # @yieldreturn Array<Object>	# Subcommand parameters
    #
    def self.subcommand(name, description, optparser=nil, &exec)
        @@subcommands[name] = [ description, optparser, exec ]
    end

    
    # Global option parser
    #
    GlobalParser = OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] CMD [opts] [args]"

        opts.separator ""
        opts.separator "Options:"
        opts.on "-h", "--help",         "Show this message" do
            puts opts
            puts ""
            puts "Commands:"
            @@subcommands.each {|name, (desc, *) |
                puts "    %-12s %s" % [ name, desc ]
            }
            puts ""
            puts "See '#{opts.program_name} CMD --help'"		\
                 " for more information on a specific command"
            puts ""
            exit
        end

        opts.on "-V", "--version",      "Show version" do
            puts opts.ver()
            exit
        end        

        opts.separator ""
        opts.separator "Global options:"
        opts.on "-o", "--output=FILE",                   "Output file"
        opts.on "-m", "--output-mode=MODE", OUTPUT_MODE,
                "Output mode (#{OUTPUT_MODE.first})",
                " Value: #{OUTPUT_MODE.join(', ')}"
        opts.on "-d", "--dat=FILE",                      "DAT file"
        opts.on "-I", "--index=FILE",                    "Index file"
        opts.on "-D", "--destdir=DIR",                   "Destination directory"
        opts.on "-f", "--force",                         "Force operation"
        opts.on '-p', '--[no-]progress',                 "Show progress"
        opts.on '-v', '--[no-]verbose',                  "Run verbosely"
    end

    
    # Program name
    PROGNAME = GlobalParser.program_name
    
    def initialize
        @verbose     = true
        @progress    = true
        @output_mode = OUTPUT_MODE.first
        @io          = $stdout
    end


    # Parse command line arguments
    #
    #
    def parse(argv)
        # Parsed option holder
        opts = {}

        # Parse global options
        GlobalParser.order!(argv, into: opts)

        # Check for subcommand
        subcommand = argv.shift&.to_sym
        if subcommand.nil?
            warn "subcommand missing"
            exit
        end
        if !@@subcommands.include?(subcommand)
            warn "subcommand \'#{subcommand}\' is not recognised"
            exit
        end

        # Process our options
        if opts.include?(:output)
            @io = File.open(opts[:output],
                            File::CREAT|File::TRUNC|File::WRONLY)
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

        # Sanitize
        if (@ouput_mode == :fancy) && !@io.tty?
            @output_mode = :text
        end

        # Parse command, and build arguments call
        _, optparser, argbuilder = @@subcommands[subcommand]
        optparser.order!(argv, into: opts) if optparser
        args = argbuilder.call(argv, **opts)

        # Call subcommand
        self.method(subcommand).call(*args)
    rescue OptionParser::InvalidArgument => e
        warn "#{PROGNAME}: #{e}"
    end

    
    # Create DAT from file
    #
    # @param file	[String]	dat file
    # @param verbose	[Boolean]	be verbose
    #
    # @return [DatFile]
    #
    def make_dat(file, verbose: @verbose, progress: @progress)
        dat = DatFile.new(file)
        if verbose
            $stderr.puts "DAT = #{dat.version}"
        end
        dat
    end



    # Potential ROM from directory.
    # @see Vault.from_dir for details
    #
    # @param romdirs   [Array<String>] 	path to rom directoris
    # @param depth     [Integer,nil]	exploration depth
    #
    # @yieldparam file [String]		file being processed
    # @yieldparam dir: [String]		directory relative to
    #
    def from_romdirs(romdirs, depth: nil, &block)
        romdirs.each {|dir| 
            Vault.from_dir(dir, depth: depth, &block)
        }
    end

    
    # Create Storage from ROMs directories
    #
    # @param romdirs	[Array<String>] array of ROMs directories
    # @param verbose	[Boolean]	be verbose
    #
    # @return [Storage]
    #
    def make_storage(romdirs, depth: nil,
                     verbose: @verbose, progress: @progress)
        vault = Vault::new
        block = ->(file, dir:) { vault.add_from_file(file, dir) }
        
        if progress
            TTY::Spinner.new("[:spinner] :file", :hide_cursor => true,
                                                 :clear       => true)
                        .run('Done!') {|spinner|
                from_romdirs(romdirs, depth: depth) {|file, dir:|
                    width = TTY::Screen.width - 8
                    spinner.update(:file => file.ellipsize(width, :middle))
                    block.call(file, dir: dir)
                }
            }
        else
            from_romdirs(romdirs, depth: depth, &block)
        end

        Storage::new(vault)
    end
    
end
end


require_relative 'cli/check'
require_relative 'cli/validate'
require_relative 'cli/index'
require_relative 'cli/rename'
require_relative 'cli/rebuild'
require_relative 'cli/repack'
require_relative 'cli/overlap'
require_relative 'cli/header'
require_relative 'cli/clean'

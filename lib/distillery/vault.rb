# SPDX-License-Identifier: EUPL-1.2

require 'set'
require 'pathname'
require 'fileutils'
require 'find'

require_relative 'rom'
require_relative 'rom-archive'

module Distillery

class Vault
    include Enumerable

    # @!visibility private
    GLOB_PATTERN_REGEX = /(?<!\\)[?*}{\[\]]/.freeze

    # List of ROM checksums
    CHECKSUMS    = ROM::CHECKSUMS

    # List of archives extensions
    ARCHIVES     = ROMArchive::EXTENSIONS

    # List of files to be ignored
    #   .dat     : dat file
    #   .index   : index file
    #   .missing : list of missing ROMs
    #   .baddump : list of baddump ROMs
    #   .extra   : list of extra ROMs
    IGNORE_FILES = Set[ '.dat', '.index',
                        '.missing', '.baddump', '.extra' ].freeze

    # List of directories to be ignored
    IGNORE_DIRS  = Set[ '.roms', '.games', '.trash' ].freeze

    # Directory pruning
    DIR_PRUNING  = Set[ '.dat' ].freeze


    # Potential ROM from directory.
    # @note file in {IGNORE_FILES}, directory in {IGNORE_DIRS},
    #       directories holding a {DIR_PRUNING} file or starting with a
    #       dot are ignored
    #
    # @param dir       [String]         path to directory
    # @param depth     [Integer,nil]    exploration depth
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir: [String]         directory relative to
    #
    def self.from_dir(dir, depth: nil)
        Find.find(dir) do |path|
            basename = File.basename(path)
            subpath  = Pathname(path).relative_path_from(dir).to_s

            # Skip/prune directory
            if    FileTest.directory?(path)
                next       if path == dir
                Find.prune if IGNORE_DIRS.include?(basename)
                Find.prune if basename.start_with?('.')
                Find.prune if !depth.nil? &&
                              subpath.split(File::Separator).size > depth
                Find.prune if DIR_PRUNING.any? { |f| File.exist?(f) }

            # Process file
            elsif FileTest.file?(path)
                next if IGNORE_FILES.include?(basename)
                yield(subpath, dir: dir) if block_given?
            end
        end
    end


    # Potential ROM from glob
    # @note file in {IGNORE_FILES}, directory in {IGNORE_DIRS},
    #       directories holding a {DIR_PRUNING} file or starting with a
    #       dot are ignored
    #
    # @param glob     [String]          ruby glob
    # @param basedir  [:guess,nil]      basedir to use when interpreting glob
    #                                   matching
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir: [String]         directory relative to
    #
    def self.from_glob(glob, basedir: :guess)
        if basedir == :guess
            gentry  = glob.split(File::SEPARATOR)
            idx     = gentry.find_index { |entry| entry =~ GLOB_PATTERN_REGEX }
            gentry  = gentry[0, idx]
            basedir = if    gentry.empty?       then nil
                      elsif gentry.first.empty? then '/'
                      else                      File.join(gentry)
                      end
        end

        # Build file list (reject ignored files and dirs)
        lst = Dir[glob].reject do |path|
            !FileTest.file?(path)                               ||
            IGNORE_FILES.include?(File.basename(path))          ||
            path.split(File::SEPARATOR)[0..-1].any? { |dir|
                IGNORE_DIRS.include?(dir) || dir.start_with?('.')
            }
        end
        # Build cut list based on directory prunning
        cutlst = lst.map { |f| File.dirname(f) }.uniq.select { |f|
            DIR_PRUNING.any? { |p| FileTest.exist?(File.join(f, p)) }
        }
        # Apply cut list
        lst.reject! { |path|
            cutlst.any? { |cut| path.start_with?("#{cut}#{File::SEPARATOR}") }
        }

        # Iterate on list
        lst.each do |path|
            subpath = if basedir.nil?
                      then path
                      else Pathname(path).relative_path_from(basedir).to_s
                      end
            yield(subpath, dir: basedir) if block_given?
        end
    end


    def initialize(roms = [])
        @cksum    = Hash[CHECKSUMS.map { |k| [ k, {} ] }]
        @roms     = []

        Array(roms).each { |rom| add_rom(rom) }
    end


    # @return [Boolean]
    def empty?
        @roms.empty?
    end


    # @return [Integer]
    def size
        @roms.size
    end


    # Iterate over each ROM
    #
    # @yieldparam rom [ROM]
    #
    # @return [self,Enumerator]
    #
    def each
        block_given? ? @roms.each { |rom| yield(rom) }
                     : @roms.each
    end


    # Construct a new ROM vault as the intersection
    #
    # @param o [Vault]  ROM vault to intersect with self
    #
    # @return [Vault]
    def &(o)
        Vault::new(@roms.select { |rom| o.match(rom) })
    end


    # Constuct a new ROM vault as the difference
    #
    # @param o [Vault]  ROM vault to substract to self
    #
    # @return [Vault]
    def -(o)
        Vault::new(@roms.reject { |rom| o.match(rom) })
    end


    # Add ROM
    #
    # @param [ROM] *roms        ROM to add
    #
    # @return self
    #
    def <<(rom)
        add_rom(rom)
    end


    # Add ROM
    #
    # @param [ROM] rom          ROM to add
    #
    # @return self
    #
    def add_rom(rom)
        # Sanity check
        raise ArgumentError, "not a ROM" unless rom.is_a?(ROM)

        # Add it to the list
        @roms << rom

        # Keep track of checksums
        @cksum.each { |type, hlist|
            hlist.merge!(rom.cksum(type) => rom) { |_, old, new|
                if Array(old).any? { |r| r.path == new.path }
                then old
                else Array(old) + [ new ]
                end
            }
        }

        # Chainable
        self
    end


    # Add ROM from file
    #
    # @param file     [String]          path to files relative to basedir
    # @param basedir  [String,nil]      base directory
    # @param archives [#include?]       archives tester
    #
    # @return [self]
    #
    def add_from_file(file, basedir = nil, archives: ARCHIVES)
        filepath = File.join(*[ basedir, file ].compact)
        romlist  = if ROMArchive.archive?(filepath, archives: archives)
                   then ROMArchive.from_file(filepath).to_a
                   else ROM.from_file(file, basedir)
                   end

        Array(romlist).each { |rom| add_rom(rom) }
    end


    # Add ROM from directory.
    # @note file in {IGNORE_FILES}, directory in {IGNORE_DIRS},
    #       directories holding a {DIR_PRUNING} file or starting with a
    #       dot are ignored
    #
    # @param dir       [String]         path to directory
    # @param depth     [Integer,nil]    exploration depth
    # @param archives  [#include?]      archives tester
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir  [String]         directory relative to
    #
    # @return [self]
    #
    def add_from_dir(dir, depth: nil, archives: ARCHIVES)
        Vault.from_dir(dir, depth: depth) do |file, dir:|
            yield(file, dir: dir) if block_given?
            add_from_file(file, dir, archives: archives)
        end
        self
    end


    # Add ROM from glob
    # @note file in {IGNORE_FILES}, directory in {IGNORE_DIRS},
    #       directories holding a {DIR_PRUNING} file or starting with a
    #       dot are ignored
    #
    # @param glob     [String]          ruby glob
    # @param basedir  [:guess,nil]      basedir to use when interpreting glob
    #                                   matching
    # @param archives [#include?]       archives tester
    #
    # @yieldparam file [String]         file being processed
    # @yieldparam dir  [String]         directory relative to
    #
    # @return [self]
    #
    def add_from_glob(glob, basedir: :guess, archives: ARCHIVES)
        Vault.from_dir(glob, basedir: basedir) do |file, dir:|
            yield(file, dir: dir) if block_given?
            add_from_file(file, dir, archives: archives)
        end
        self
    end


    # List of ROM with loosely defined (ie: with some missing checksum)
    #
    # @return [Array<ROM>,nil]
    #
    def with_partial_checksum
        @roms.reject(&:checksums?)
    end


    # Check if we have some headered ROM.
    #
    # @return [Integer]                 only some ROMs are headered
    # @return [true]                    all ROMs are headered
    # @return [false]                   no headered ROM
    #
    def headered
        size = @roms.select(&:headered?).size

        if    size == 0          then false
        elsif size == @roms.size then true
        else                          size
        end
    end


    # Return list of matching ROMs.
    #
    # @param query [Hash{Symbol=>String}]       Hash of checksums to match with
    #
    # @return [Array<ROM>]              list of matching ROMs
    # @return [nil]                     if no match
    #
    def cksummatch(query)
        # Look for matching checksum
        CHECKSUMS.each do |type|
            if (q = query[type]) && (r = @cksum[type][q])
                return Array(r)
            end
        end

        # No match
        nil
    end


    # Return list of matching ROMs.
    #
    # @param rom [ROM]                  ROM to match with
    #
    # @return [Array<ROM>]              list of matching ROMs
    # @return [nil]                     if no match
    #
    def rommatch(rom)
        cksummatch(rom.cksums)
    end


    # Return list of matching ROMs.
    #
    # @param query [Hash{Symbol=>String},ROM]   Hash of checksums or ROM
    #                                           to match with
    #
    # @yieldparam rom [ROM]                     ROM that has been saved
    #
    # @return [Array<ROM>]              list of matching ROMs
    # @return [nil]                     if no match
    #
    def match(query)
        case query
        when Hash then cksummatch(query)
        when ROM  then rommatch(query)
        else raise ArgumentError
        end
    end


    # Copy ROM to filesystem using hash as name.
    #
    # @param dir      [String]          directory used for saving
    # @param part   [:all,:header,:rom] which part of the ROM file to save
    # @param subdir   [Boolean,Integer,Proc] use subdirectory
    # @param pristine [Boolean]         should existing directory be removed
    # @param force    [Boolean]         remove previous file if necessary
    #
    # @yieldparam rom [ROM]             ROM saved
    # @yieldparam copied: [Boolean]     was the copy performed
    # @yieldparam as: [String]          name used to save content
    #
    # @return [self]
    #
    def copy(dir, part: :all, subdir: false, pristine: false, force: false)
        # Directory
        FileUtils.remove_dir(dir) if     pristine        # Create clean env
        Dir.mkdir(dir)            unless Dir.exist?(dir) # Ensure directory

        # Fill directory.
        # -> We have the physical ROMs, so we have all the checksums
        #    except if the file is an header without rom content
        @roms.reject(&:virtual?).each do |rom|
            hash    = rom.fshash
            destdir = dir
            dirpart = case subdir
                      when nil, false then nil
                      when true       then hash[0..3]
                      when Integer    then hash[0..subdir]
                      when Proc       then subdir.call(rom)
                      else raise ArgumentError, "unsupported subdir type"
                      end

            if dirpart
                # Update destination directory
                destdir = File.join(destdir, *dirpart)
                # Ensure destination directory exists
                FileUtils.mkdir_p(destdir)
            end

            # Destination file
            dest = File.join(destdir, hash)

            # If the file exist, it is the right file, as it is
            # named from it's hash (ie: content)
            copied = if force || !File.exist?(dest)
                         rom.copy(dest, part: part, force: force)
                     else
                         false
                     end

            yield(rom, as: dest, copied: copied) if block_given?
        end

        self
    end


    # Dumping of ROM vault entries
    #
    # @param compact [Boolean]
    #
    # @return [self]
    #
    # @yieldparam group   [String]
    # @yieldparam entries [Array<String>]
    #
    def dump(compact: false)
        self.each.inject({}) { |grp, rom|
            grp.merge(rom.path.storage => [ rom ]) { |_, old, new| old + new }
        }.each { |storage, roms|
            size = case roms.first.path
                   when ROM::Path::Archive then roms.first.path.archive.size
                   end

            if storage.nil?
                roms.each { |rom| yield(rom.path.entry, nil) }
            elsif compact && (size == roms.size)
                yield(storage)
            else
                yield(storage, roms.map { |r| r.path.entry })
            end
        }
        self
    end


    # Generate ROM index.
    #
    # @return [Hash{String=>Hash{Symbol=>Object}}]
    #
    def index
        each.to_h { |rom|
            # Establish file name
            file  = rom.path.to_s
            # Get metadata
            mtime = File.mtime(rom.path.storage).strftime('%F %T.%N %Z')
            meta  = rom.info(cksum: :hex).merge(:timestamp => mtime)
            # Indexed data
            [ file,  meta ]
        }
    end


    protected

    def roms
        @roms
    end
end

end

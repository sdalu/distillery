# SPDX-License-Identifier: EUPL-1.2
# coding: utf-8
# frozen_string_literal: true

require 'set'
require 'securerandom'

require_relative 'archiver/archive'

begin
    require 'mimemagic'
rescue LoadError
    # That's ok, it's an optional commponent
end


module Distillery

# @abstract
# Allow processing of archives
#
class Archiver
    include Enumerable

    # Standard error for Archiver class and subclasses
    class Error                 < StandardError
    end

    # Notification of not archiver found
    class ArchiverNotFound      < Error
    end

    # Excution error for external process
    class ExecError             < Error
    end

    # Processing error when dealing with archive
    class ProcessingError       < Error
    end

    # Operation not supported
    class OperationNotSupported < Error
    end
    
    # InputStream used by Archiver#reader
    class InputStream
        def initialize(io)
            @io = io
        end


        # Read data
        #
        # @param length [Integer, nil]  number of bytes to read,
        #                               whole data if nil
        # @param outbuf [String, nil]   output buffer
        #
        # @return [String, nil]         data or nil if end of stream
        #
        def read(length = nil, outbuf = nil)
            @io.read(length, outbuf)
        end
    end


    # OutputStream used by Archiver#writer
    class OutputStream
        def initialize(io)
            @io = io
        end


        # Write data
        #
        # @param data [String]                  date to write
        #
        # @return [Integer]                     number of bytes written
        #
        def write(data)
            @io.write(data)
        end
    end


    # @!visibility private
    @@logger     = nil

    # @!visibility private
    @@providers  = []

    # @!visibility private
    @@archivers  = Set.new

    # @!visibility private
    @@mimetypes  = {}

    # @!visibility private
    @@extensions = {}



    # Register a logger
    #
    # @param logger [Logger,nil]        logger
    #
    # @return logger
    #
    def self.logger=(logger)
        @@logger = logger
    end


    # Get the regisered logger
    #
    # @return [Logger,nil]
    #
    def self.logger
        @@logger
    end


    # Add an archiver provider class
    #
    # @param provider [Class]           archiver provider
    #
    # @return [self]
    #
    def self.add(provider)
        @@providers << provider
        self
    end


    # List of archivers' providers in loading order.
    #
    # @return [Array<Class>]                    Archiver class
    #
    def self.providers
        # Could be done by looking at constants
        #   constants.lazy.map {|c| const_get(c) }.select {|k| k < self }.to_a
        # But we want to keep loading order
        @@providers
    end


    # Perform automatic registration of all the archive providers
    #
    # @return [self]
    #
    def self.registering
        self.providers.each do |p|
            p.registering
        end
        self
    end


    # Register an archiver.
    #
    # @param archiver	[Archiver]		Archiver to register
    # @param warnings	[Boolean]		Emit warning when overriding
    #
    def self.register(archiver, warnings: true)
        # Notifier
        notify = if warnings
                     lambda { |type, key, old, new|
                         oname = old.class.name.split('::').last
                         nname = new.class.name.split('::').last
                         Archiver.logger&.warn do
                             "#{self} overriding #{type} for #{key}" \
                             " [#{oname} -> #{nname}]"
                         end
                     }
                 end

        # Add archiver
        @@archivers.add(archiver)

        # Register mimetypes
        Array(archiver.mimetypes).each do |mt|
            @@mimetypes.merge!(mt => archiver) do |key, old, new|
                notify&.call('mimetype', key, old, new)
                new
            end
        end
        # Register extensions
        Array(archiver.extensions).each do |ext|
            @@extensions.merge!(ext.downcase => archiver) do |key, old, new|
                notify&.call('extension', key, old, new)
                new
            end
        end
        # Return archiver
        archiver
    end


    # List of registered archivers
    #
    # @return [Array<Archiver>]
    #
    def self.archivers
        @@archivers.to_a
    end


    # Archiver able to process the selected mimetype
    #
    def self.for_mimetype(mimetype)
        @@mimetypes[mimetype]
    end


    # Archiver able to process the selected extension
    #
    def self.for_extension(extension)
        extension = extension[1..-1] if extension[0] == '.'
        @@extensions[extension.downcase]
    end


    # Archiver able to process the selected file.
    #
    # @param [String] file      archive file tpo consider
    #
    # @return [Archiver]        archiver to use for processing file
    # @return [nil]             no matching archiver found
    #
    def self.for_file(file)
        # Find by extension
        parts      = File.basename(file).split('.')
        extlist    = 1.upto(parts.size - 1).map { |i| parts[i..-1].join('.') }
        archiver   = extlist.lazy.map  { |ext| self.for_extension(ext) }
                                 .find { |arc| !arc.nil?               }

        # Find by mimetype if previously failed
        archiver ||= if defined?(MimeMagic)
                         begin
                             File.open(file, File::RDONLY) do |io|
                                 self.for_mimetype(MimeMagic.by_magic(io))
                             end
                         rescue Errno::ENOENT
                             # File doesn't exists
                             # => unable to infer archiver
                         end
                     end

        # Return found archiver (or nil)
        archiver
    end


    # Return an archive instance of the specified file, or invokes the block
    # with the archive instance passed as parameter.
    #
    # @overload for(file)
    #  @param file [String]             archive file
    #  @param archiver [Archiver]	force use of the specified archiver
    #                                   otherwise infer it from the file name
    #
    #  @raise [ArchiverNotFound]        an archiver able to process this file
    #                                   has not been found
    #
    #  @return [Archive]                archive instance
    #
    # @overload for(file)
    #  @param file [String]             archive file
    #  @param archiver [Archiver]	force use of the specified archiver
    #                                   otherwise infer it from the file name
    #
    #  @yieldparam archive [Archive]    archive instance
    #
    #  @raise [ArchiverNotFound]        an archiver able to process this file
    #                                   has not been found
    #
    #  @return [self]
    #
    def self.for(file, archiver = nil)
        archive = Archive.new(file, archiver)
        if block_given?
            yield(archive)
            self
        else
            archive
        end
    end


    # Repack an archive.
    #
    # @param file	[String]	archive file to process
    # @param type	[String]	archive type (extension)
    # @param dryrun	[Boolean]	perform dry-run instead
    #
    # @return [Boolean]			operation successful
    #
    # @raise [ArchiverNotFound]         an archiver able to process this file
    #                                   or the requested type was not found
    # @raise [Errno::EEXIST]            a different archive with this name
    #                                   already exists
    #
    def self.repack(file, type, dryrun: false)
        # Get file archiver now, as file can be renamed later
        filearchiver = Archiver.for_file(file)
        
        # Destination
        dstfile  = file.dup
        dstfile += ".#{type}" unless dstfile.sub!(/\.[^.\/]*$/, ".#{type}")
        dst      = Archiver.for(dstfile)

        # If source and destination are the same
        #  - move source out of the way as we could recompress
        #    using another algorithm
        srcfile = if file == dstfile
                      (file +'.'+ SecureRandom.alphanumeric(10)).tap {|newfile|
                          File.rename(file, newfile) unless dryrun
                      }
                  elsif File.exist?(dstfile)
                      raise Errno::EEXIST
                  else
                      file
                  end

        # Get archiver for source
        #  It is safe to check here, as if srcfile has been renamed
        #  it means that archiver for it exists as it was test for dstfile
        src = Archiver.for(srcfile, filearchiver)

        # Dry run ?
        return true if dryrun

        # Perform repacking
        begin
            # Repack
            src.each do |entry, i|
                dst.writer(entry) do |o|
                    while data = i.read(32 * 1024)
                        o.write(data)
                    end
                end
            end
            # Remove old archive
            File.unlink(srcfile)

        #  Something went wrong, put everything back
        rescue
            # Notify of damaged file
            Archiver.logger&.warn "File '#{file}' probably damaged"
            # Remove build archive
            File.unlink(dstfile) if File.exist?(dstfile)
            # Put back original archive name if necessary
            File.rename(srcfile, file) if file != srcfile
            # Stop here
            return false
        end
    
        # Done
        true
    end


    
    def initialize
        raise 'abstract class'
    end


    # List of low-level supported operation (list, read, write, delete, rename)
    #
    # @return [Set<Symbol>]
    #
    def write_enabled
        raise 'abstract method'
    end


    # List of supported extensions
    #
    # @return [Array<String>]
    #
    def extensions
        raise 'abstract method'
    end


    # List of supported mimetypes
    #
    # @return [Array<String>]
    #
    def mimetypes
        raise 'abstract method'
    end


    # Iterate over each archive entry
    #
    # @param file [String]              archive file
    #
    # @yieldparam entry [String]
    # @yieldparam io    [InputStream]
    #
    # @return [self,Enumerator]
    #
    def each(file)
        raise 'abstract method'
    end


    # Check if the archive exists
    #
    # @param file [String]              archive file
    #
    # @return [Boolean]
    #
    def exist?(file)
        File.exist?(file)
    end


    # Check if the archive contains no entry
    #
    # @param file [String]              archive file
    #
    # @return [Boolean]
    #
    def empty?(file)
        each(file).none?
    end


    # Check if the archive contains the specified entry
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    #
    # @return [Boolean]
    #
    def include?(file, entry)
        each(file).any? { |a_entry, _| a_entry == entry }
    end


    # List archive entries
    #
    # @param file [String]              archive file
    #
    # @return [Array<String>]
    #
    def entries(file)
        each(file).map { |a_entry, _| a_entry }
    end


    # Allow to perform read operation on an archive entry
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    #
    # @yieldparam io [InputStream]      input stream for reading
    #
    # @return                           block value
    #
    def reader(file, entry)
        _, a_io = each(file).find { |a_entry, _| a_entry == entry }
        yield(a_io) if a_io
    end


    # Allow to perform write operation on an archive entry
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    #
    # @yieldparam io [OutputStream]     output stream for writing
    #
    # @return                           block value
    #
    def writer(file, entry)
        raise OperationNotSupported
    end

    
    # Check if two entries are identical
    #
    # @param file    [String]             archive file
    # @param entry_1 [String]             entry 1
    # @param entry_2 [String]             entry 2
    #
    # @return [Boolean]
    #
    def same?(file, entry_1, entry_2)
        reader(file, entry_1) do |i_1|
            reader(file, entry_2) do |i_2|
                loop {
                    d_1 = i_1.read(32 * 1024)
                    d_2 = i_2.read(32 * 1024)
                    break false if d_1 != d_2
                    break true  if d_1.nil?
                }
            end
        end
    end
    
    # Delete the entry from the archive
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    #
    # @return [Boolean]         operation status
    #
    def delete!(file, entry)
        raise OperationNotSupported unless write_enabled

        # Check for no-op
        return true if !include?(file, entry)

        # Copy whole archive, excluding selected entry
        # to a temporary file
        tmpfile = file + '.delete-' + SecureRandom.alphanumeric(10)
        
        each(file) do |a_entry, a_io|
            next if a_entry == entry
            writer(tmpfile, a_entry) do |o|
                IO.copy_stream(a_io, o)
            end
        end

        # Replace original archive
        File.rename(tmpfile, file)
        true

    ensure
        File.unlink(tmpfile) if tmpfile && File.exist?(tmpfile)
    end


    # Create a copy of the archive entry
    #
    # @param file      [String]         archive file
    # @param entry     [String]         entry name
    # @param new_entry [String]         new entry name
    # @param force [Boolean]            remove previous entry if necessary
    #
    # @return [Boolean]         operation status
    #
    def copy(file, entry, new_entry, force: false)
        raise OperationNotSupported unless write_enabled

        # Deal with existing new entry
        if include?(file, new_entry)
            # If same, consider it done (no-op)
            return true  if same?(file, entry, new_entry)
            # If force not enabled, stop here
            return false if !force

            # Ensure existing entry is removed
            delete!(file, new_entry)
        end

        # Perform copy
        reader(file, entry) do |i|
            writer(file, new_entry) do |o|
                IO.copy_stream(i, o)
            end
        end

        # Done
        true
    end

    
    # Rename archive entry
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    # @param new_entry [String]         new entry name
    # @param force [Boolean]            remove previous entry if necessary
    #
    # @return [Boolean]         operation status
    #
    def rename(file, entry, new_entry, force: false)
        copy(file, entry, new_entry, force: force) &&
            delete!(file,entry)
    end


  protected

    def exist!(file)
        raise Errno::ENOENT unless exist?(file)
    end
    def include!(file, entry)
        raise Errno::ENOENT unless include?(file, entry)
    end
  

end
end

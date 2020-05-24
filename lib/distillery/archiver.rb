# SPDX-License-Identifier: EUPL-1.2
# coding: utf-8
# frozen_string_literal: true

require 'set'

require_relative 'archiver/archive'

module Distillery

# @abstract
# Allow processing of archives
#
class Archiver
    include Enumerable

    # Standard error for Archiver class and subclasses
    class Error            < StandardError
    end

    # Notification of not archiver found
    class ArchiverNotFound < Error
    end

    # Excution error for external process
    class ExecError        < Error
    end

    # Processing error when dealing with archive
    class ProcessingError  < Error
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
        #
        # @return [String, nil]         data or nil if end of stream
        #
        def read(length = nil)
            @io.read(length)
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
    # @param [Archiver] archiver                Archiver to register
    # @param [Boolean] warnings                 Emit warning when overriding
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
        Array(archiver.mimetypes).each {|mt|
            @@mimetypes.merge!(mt => archiver) do |key, old, new|
                notify&.call('mimetype', key, old, new)
                new
            end
        }
        # Register extensions
        Array(archiver.extensions).each {|ext|
            @@extensions.merge!(ext.downcase => archiver) do |key, old, new|
                notify&.call('extension', key, old, new)
                new
            end
        }
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
        archiver   = extlist.lazy.map  {|ext| self.for_extension(ext) }
                                 .find {|arc| !arc.nil?               }

        # Find by mimetype if previously failed
        archiver ||= if defined?(MimeMagic)
                         begin
                             File.open(file) {|io|
                                 self.for_mimetype(MimeMagic.by_magic(io))
                             }
                         rescue Errno::ENOENT
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
    #
    #  @raise [ArchiverNotFound]        an archiver able to process this file
    #                                   has not been found
    #
    #  @return [Archive]                archive instance
    #
    # @overload for(file)
    #  @param file [String]             archive file
    #
    #  @yieldparam archive [Archive]    archive instance
    #
    #  @raise [ArchiverNotFound]        an archiver able to process this file
    #                                   has not been found
    #
    #  @return [self]
    #
    def self.for(file)
        archive = Archive.new(file)
        if block_given?
            yield(archive)
            self
        else
            archive
        end
    end


    def initialize
        raise 'abstract class'
    end


    # List of supported extensions
    #
    # @return [Array<String>]
    #
    def extensions
        [ 'zip' ]
    end


    # List of supported mimetypes
    #
    # @return [Array<String>]
    #
    def mimetypes
        [ 'application/zip' ]
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


    # Check if the archive contains no entry
    #
    # @param file [String]              archive file
    #
    # @return [Boolean]
    #
    def empty?(file)
        each(file).none?
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
        each(file) do |a_entry, a_io|
            next unless a_entry == entry
            return yield(a_io)
        end
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
        nil
    end


    # Delete the entry from the archive
    #
    # @param file  [String]             archive file
    # @param entry [String]             entry name
    #
    # @return [Boolean]         operation status
    #
    def delete!(file, entry)
        false
    end
end
end

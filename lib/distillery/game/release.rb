# SPDX-License-Identifier: EUPL-1.2

module Distillery

# Information about release
#
class Release
    # @!visibility private
    @@regions = Set.new

    # List all assigned region code.
    #
    # @return [Set<String>]             set of region code
    #
    def self.regions
        @@regions
    end


    # Create a new instance of Release.
    #
    # @param name   [String]            release name
    # @param region [String]            region of release
    #
    def initialize(name, region:)
        @name   = name
        @region = region

        @@regions.add(region)
    end

    # Release name
    # @return [String]
    attr_reader :name

    # Region of release
    # @return [String]
    attr_reader :region

end

end

# SPDX-License-Identifier: EUPL-1.2

require_relative 'game/release'

module Distillery

# Information about game
#
class Game
    # Create a new instance of Game.
    #
    # @param name     [String]
    # @param roms     [ROM]
    # @param releases [Array<Game::Release>,nil]
    # @param cloneof  [String,nil]
    def initialize(name, *roms, releases: nil, cloneof: nil)
        raise ArgumentError if name.nil?

        @name     = name
        @roms     = roms
        @releases = releases
        @cloneof  = cloneof
    end


    # @return [Integer]
    def hash
        @name.hash
    end


    def eql?(o)
        @name.eql?(o.name)
    end


    # String representation
    # @return [String]
    def to_s
        @name
    end


    # @return [String]
    attr_reader :name

    # @return [Array<ROM>]
    attr_reader :roms

    # @return [Array<Release>]
    attr_reader :releases

    # @return [String]
    attr_reader :cloneof


    # Iterate over ROMs used be the game
    #
    # @yieldparam rom [ROM]
    #
    # @return [self,Enumerator]
    #
    def each_rom
        block_given? ? @roms.each {|r| yield(r) }
                     : @roms.each
    end


end

end 

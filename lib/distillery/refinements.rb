# SPDX-License-Identifier: EUPL-1.2

module Distillery

module StringEllipsize
    refine ::String do
        def ellipsize(width, position = :end, ellipsis: '...')
            # Sanity check
            unless [ :begin, :middle, :end ].include?(position)
                raise ArgumentError, "unsupported position (#{position})"
            end

            # Is there a need to ellipsize ?
            return self if self.size <= width

            # Ellipsis too big?
            if ellipsis&.size > width
                return ellipsis
            end

            # Deal with nil-ellipsis
            ellipsis ||= ''

            # Perform ellipsis
            str     = self.dup
            delsize = self.size - width + ellipsis.size

            case position
            when :begin  then str[0, delsize]       = ellipsis
            when :middle then str[width/2, delsize] = ellipsis
            when :end    then str[-delsize..-1]     = ellipsis
            end

            # Return ellipsized string
            str
        end
    end

end

end

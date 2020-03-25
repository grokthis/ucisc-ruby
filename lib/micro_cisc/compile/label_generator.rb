module MicroCisc
  module Compile
    class LabelGenerator
      def initialize
        @labels = []
        @count = 0
      end

      def push_context
        @count += 1
        @labels << "{#{@count}"
      end

      def pop_context
        @labels << last_open.sub('{', '}')
      end

      def end_label
        last_open.sub('{', '}')
      end

      def start_label
        last_open
      end

      def last_open
        if @labels.empty?
          raise ArgumentException, "No open label context"
        end
        # Go backwards until we find an open that we didn't see the close for first
        i = @labels.size - 1
        closed = nil
        while(i >= 0)
          if @labels[i].start_with?('}')
            closed = @labels[i]
          elsif !closed
            return @labels[i]
          elsif closed && @labels[i].end_with?(closed[1..-1])
            closed = nil
          else
            raise 'Invalid state, contexts are out of order'
          end
          i -= 1
        end
      end
    end
  end
end

module MicroCisc
  module Compile
    class LabelGenerator
      def initialize(default_context)
        @default_context = default_context
        @labels = []
        @count = 0
      end

      def push_context(prefix = @default_context)
        @labels << prefix
      end

      def pop_context(prefix = @default_context)
        if !@labels.rindex(prefix)
          raise ArgumentException, "Context #{prefix} is invalid."
        end
        @labels[@labels.rindex(prefix)] = "-#{prefix}"
      end

      def end_label
        if @labels.empty?
          raise ArgumentException, "No open label context"
        end
        count = @labels.size.to_s(16).upcase
        "}-#{@labels.last}:#{count}"
      end

      def start_label
        if @labels.empty?
          raise ArgumentException, "No open label context"
        end
        count = @labels.size.to_s(16).upcase
        "{-#{@labels.last}:#{count}"
      end
    end
  end
end

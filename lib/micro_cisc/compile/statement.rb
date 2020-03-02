module MicroCisc
  module Compile
    class Statement
      attr_reader :original, :minimal

      def initialize(label_generator, statement)
        @label_generator = label_generator
        @original = statement
        @minimal = filter_comments(statement)
      end

      def filter_comments(instruction)
        # Remove all inline comments
        instruction = instruction.to_s.strip.gsub(/\/[^\/]*\//, '')
        # Remove all word comments
        instruction = instruction.gsub(/'[^\s]*/, '')
        # Remove all line comments
        instruction = instruction.gsub(/#.*/, '')
        # Single space
        instruction.gsub(/\s+/, ' ')
      end

      def parse
        if @minimal.start_with?('(')
          parse_function_call
        else
          [Instruction.new(@label_generator, minimal, original)]
        end
      end

      def parse_function_call
        match = /\(\s*(?<stack>[^\s]+)\s+(?<label>[a-zA-Z_][a-zA-Z0-9_\-@$!%]*)\s*(?<args>[^)]*)/.match(minimal)
        label = match['label']
        stack = match['stack']
        args = match['args'].split(',').map(&:strip)

        instruction = "0 0.reg #{2 * args.size + 4}.imm #{stack} 1.inc 3.eff"
        return_address = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}")
        stack_delta = 2
        args = args.reverse.map.each do |arg|
          instruction = "0 #{arg} #{stack} 1.inc 3.eff"
          offset = (arg.start_with?(stack) ? stack_delta : 0)
          stack_delta += 2
          Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}", offset)
        end
        instruction = "0 0.reg #{label}.disp 0.reg 0.inc 3.eff"
        call = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}")
        [return_address] + args + [call]
      end
    end
  end
end

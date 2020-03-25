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

      IMM_REGEX = / (0x){0,1}(?<imm_val>[0-9A-Fa-f])\.imm/

      def parse_function_call
        match = /\(\s*(?<stack>[^\s]+)\s+(?<label>[a-zA-Z_][a-zA-Z0-9_\-@$!%]*)\s*(?<args>[^)]*)/.match(minimal)
        label = match['label']
        stack = match['stack']
        args = match['args'].split(',').map(&:strip)

        instruction = "0 0.reg #{args.size + 2}.imm #{stack} 1.push"
        return_address = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}")
        stack_delta = 1
        args = args.map.each do |arg|
          is_stack = arg.start_with?(stack)
          if is_stack
            offset = stack_delta
            if arg_imm = IMM_REGEX.match(arg)
              arg_imm = arg_imm['imm_val'].to_i(16)
              arg = arg.sub(IMM_REGEX, '')
            else
              arg_imm = 0
            end
            offset_immediate = (offset + arg_imm) > 0 ? " #{(offset + arg_imm).to_s(16).upcase}.imm" : ''
            arg = "#{arg}#{offset_immediate}"
          end
          instruction = "0 #{arg} #{stack} 1.push"
          stack_delta += 1
          Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}")
        end
        instruction = "0 0.reg #{label}.disp 0.reg"
        call = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}")
        [return_address] + args + [call]
      end
    end
  end
end

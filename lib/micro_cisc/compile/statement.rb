module MicroCisc
  module Compile
    class Statement
      SUGAR_REGEX = /(?<name>\$[^\s]+)\s+(?<op>as|=)\s+(?<param>.+)/
      FUNCTION_REGEX = /(?<stack>[^\s]+)\s+<=\s+(?<label>[a-zA-Z_][a-zA-Z0-9_\-@$!%]*)\s*\(\s*(?<args>[^)]*)/
      IMM_REGEX = / (0x){0,1}(?<imm_val>[0-9A-Fa-f])\.imm/
      attr_reader :original, :minimal

      def initialize(label_generator, statement, sugar)
        @label_generator = label_generator
        @original = statement
        @minimal = filter_comments(statement)
        @sugar = sugar
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
        if FUNCTION_REGEX =~ @minimal
          parse_function_call
        elsif SUGAR_REGEX =~ @minimal
          match = SUGAR_REGEX.match(@minimal)
          name = match['name']
          if match['op'] == 'as'
            @sugar[name] = match['param']
            []
          else
            @minimal = match['param']
            instruction = Instruction.new(@label_generator, minimal, original, @sugar)
            dest = instruction.dest
            if [1, 2, 3].include?(dest)
              @sugar[name] = "#{dest}.mem"
            else
              dest -= 4 if dest > 4
              @sugar[name] = "#{dest}.reg"
            end
            [instruction]
          end
        else
          [Instruction.new(@label_generator, minimal, original, @sugar)]
        end
      end

      def parse_function_call
        match = FUNCTION_REGEX.match(@minimal)
        label = match['label']
        stack = match['stack']
        args = match['args'].split(',').map(&:strip)

        instruction = "copy 0.reg 2.imm #{stack} push"
        return_address = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}", @sugar)
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
          instruction = "copy #{arg} #{stack} push"
          stack_delta += 1
          Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}", @sugar)
        end
        instruction = "copy 0.reg #{label}.disp 0.reg"
        call = Instruction.new(@label_generator, instruction, "  #{instruction} # #{original}", @sugar)
        args + [return_address] + [call]
      end
    end
  end
end

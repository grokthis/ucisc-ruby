module MicroCisc
  module Compile
    class Statement
      SUGAR_REGEX = /(?<name>(\$|&)[^\s\[\]]+)\s+(?<op>as|=)\s+(?<param>.+)/
      FUNCTION_REGEX = /(?<stack>[^\s\[\]]+)\s*(\[(?<words>[0-9]+)\]){0,1}\s+<=\s+(?<label>[a-zA-Z_][a-zA-Z0-9_\-@$!%]*)\s*\(\s*(?<args>[^)]*)/
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

      def create_variable(name, arg)
        if arg.end_with?("mem") || arg.end_with?("reg")
          name = name[1..-1]
          arg = arg[0..-4]

          @sugar["$#{name}"] = "#{arg}mem"
          @sugar["&#{name}"] = "#{arg}reg"
        else
          @sugar[name] = arg
        end
      end

      def parse
        if FUNCTION_REGEX =~ @minimal
          parse_function_call
        elsif SUGAR_REGEX =~ @minimal
          match = SUGAR_REGEX.match(@minimal)
          name = match['name']
          if match['op'] == 'as'
            create_variable(name, match['param'])
            []
          elsif match['op'] == '='
            @minimal = match['param']
            instruction = Instruction.new(@label_generator, minimal, original, @sugar)
            dest = instruction.dest
            if [1, 2, 3].include?(dest)
              create_variable(name, "#{dest}.mem")
            else
              dest -= 4 if dest > 4
              create_variable(name, "#{dest}.reg")
            end
            [instruction]
          else
            raise ArgumentError, "Invalid syntax declaration: #{@minimal}"
          end
        else
          [Instruction.new(@label_generator, @minimal, original, @sugar)]
        end
      end

      def parse_function_call
        match = FUNCTION_REGEX.match(@minimal)
        label = match['label']

        stack = match['stack']
        stack = @sugar[stack] if @sugar[stack]
        raise ArgumentError, "Invalid stack param, mem register expected: #{stack}" unless stack =~ /^[1-3]\.mem$/
        stackp = stack.sub('mem', 'reg')

        return_words = match['words'].to_i
        args = match['args'].split(',').map(&:strip)

        instructions = []
        if return_words > 0
          instruction = "copy #{stackp} -#{return_words}.imm #{stackp}"
          instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # return vars - #{original}", @sugar)
        end

        instruction = "copy 0.reg #{args.size + 2}.imm #{stack} push"
        instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # return addr - #{original}", @sugar)

        stack_delta = 1 + return_words
        args = args.each do |arg|
          arg = arg.split(' ').map { |a| @sugar[a] || a }.join(' ')
          is_stack = arg.start_with?(stack)
          if is_stack
            offset = stack_delta
            if arg_imm = IMM_REGEX.match(arg)
              arg_imm = arg_imm['imm_val'].to_i(16)
              arg = arg.sub(IMM_REGEX, '')
            else
              arg_imm = 0
            end
            offset_immediate = (offset + arg_imm) > 0 ? " #{(offset + arg_imm)}.imm" : ''
            arg = "#{arg}#{offset_immediate}"
          end
          instruction = "copy #{arg} #{stack} push"
          stack_delta += 1
          instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # push arg - #{original}", @sugar)
        end
        instruction = "copy 0.reg #{label}.disp 0.reg"
        instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # call - #{original}", @sugar)
        instructions
      end
    end
  end
end

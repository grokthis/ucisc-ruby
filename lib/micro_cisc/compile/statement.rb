module MicroCisc
  module Compile
    class Statement
      SUGAR_REGEX = /(?<names>(\$|&)[^\s\[\]]+(\s*,\s*(\$|&)[^\s\[\]]+)*)\s+(?<op>as|=)\s+(?<param>.+)/
      FUNCTION_REGEX = /(?<stack>[^\s\[\]]+)\s*(\[(?<words>[0-9]+)\]){0,1}\s+<=\s+(?<label>[a-zA-Z_][a-zA-Z0-9_\-@$!%]*)\s*\(\s*(?<args>[^)]*)/
      IMM_REGEX = / (?<imm_val>-{0,1}(0x){0,1}[0-9A-Fa-f])\.imm/
      attr_reader :original, :minimal

      def initialize(label_generator, statement, indexed_vars, equivalents)
        @label_generator = label_generator
        @original = statement
        @minimal = filter_comments(statement)
        @indexed_vars = indexed_vars
        @equivalents = equivalents
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

      def normalize(arg, delta)
        imm_matches = arg.scan(IMM_REGEX).flatten
        imm_val = imm_matches.map(&:to_i).sum + delta
        arg = arg.gsub(IMM_REGEX, '').strip
        [arg, imm_val]
      end

      def create_variable(name, arg, delta)
        unless arg.include?("mem") || arg.include?("reg")
          raise ArgumentError, "Indexed variable reference is not allowed for non-register arguments, use 'as' instead"
        end

        arg = normalize(arg, delta)
        imm_val = arg.last
        # remove mem/reg part
        arg_num = arg.first[0..-4]
        name = name[1..-1]

        mem_name = "$#{name}"
        ref_name = "&#{name}"
        @equivalents.delete(mem_name)
        @equivalents.delete(ref_name)
        @indexed_vars[mem_name] = ["#{arg_num}mem", imm_val]
        @indexed_vars[ref_name] = ["#{arg_num}reg", imm_val]
      end

      def create_equivalent(name, arg, delta)
        arg = normalize(arg, delta)
        if arg.first.include?("mem") || arg.first.include?("reg")
          imm_val = arg.last
          # remove mem/reg part
          arg_num = arg[0][0..-4]
          name = name[1..-1]

          mem_name = "$#{name}"
          ref_name = "&#{name}"
          @indexed_vars.delete(mem_name)
          @indexed_vars.delete(ref_name)

          imm_str = " #{imm_val}.imm" if imm_val > 0
          @equivalents[mem_name] = "#{arg_num}mem#{imm_str}"
          @equivalents[ref_name] = "#{arg_num}reg#{imm_str}"
        else
          @indexed_vars.delete(name)
          @equivalents[name] = arg.first
        end
      end

      def update_variable(arg, delta)
        arg = arg.sub('reg', 'mem')
        ['mem', 'reg'].each do |type|
          variable = arg.sub('mem', type)
          @indexed_vars.each do |name, value|
            value[1] += delta if value.first == variable
          end
        end
      end

      def get_var(name)
        val = @equivalents[name]
        val ||=
          begin
            pair = @indexed_vars[name]
            "#{pair.first} #{pair.last}.imm" if pair
          end
        val || name
      end

      def parse
        instruction = nil
        names = []
        op = nil
        if FUNCTION_REGEX =~ @minimal
          return parse_function_call
        elsif SUGAR_REGEX =~ @minimal
          match = SUGAR_REGEX.match(@minimal)
          op = match['op']
          names = match['names'].split(',').map(&:strip)

          @minimal = match['param']
          if minimal.start_with?('copy') || minimal.start_with?('compute')
            instruction = Instruction.new(@label_generator, @minimal, original, self)
          else
            var = match['param']
            imm_match = IMM_REGEX.match(var)
            imm_val = imm_match ? imm_match['imm_val'].to_i : 0
            var = var.to_s.gsub(IMM_REGEX, '').strip
            @minimal = "#{get_var(var)}#{" #{imm_val}.imm" if imm_val != 0}"
          end
        else
          instruction = Instruction.new(@label_generator, @minimal, original, self)
        end
        if instruction && instruction.instruction?
          dest = instruction.dest
          if instruction.inc && instruction.inc > 0
            if dest > 4
              # pop
              update_variable("#{dest - 4}.mem", -1)
            else
              # push
              update_variable("#{dest}.mem", 1)
            end
          end
          if minimal.start_with?('copy') && dest > 4 && instruction.src == dest
            # Manually modifying a register
            update_variable("#{dest - 4}.mem", -1 * instruction.immediates.first)
          end
          dest -= 4 if dest > 4
          @minimal = "#{dest}.mem"
        end
        names.each_with_index do |name, index|
          if op == 'as'
            create_equivalent(name, @minimal, index)
          elsif op == '='
            create_variable(name, @minimal, index)
          end
        end
        [instruction].compact
      end

      def parse_function_call
        match = FUNCTION_REGEX.match(@minimal)
        label = match['label']

        stack = match['stack']
        stack = get_var(stack)
        raise ArgumentError, "Invalid stack param, mem register expected: #{stack}" unless stack =~ /^[1-3]\.mem$/
        stackp = stack.sub('mem', 'reg')

        return_words = match['words'].to_i
        args = match['args'].split(',').map(&:strip)

        instructions = []
        if return_words > 0
          instruction = "copy #{stackp} -#{return_words}.imm #{stackp}"
          instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # return vars - #{original}", self)
        end

        instruction = "copy 0.reg #{args.size + 2}.imm #{stack} push"
        instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # return addr - #{original}", self)

        stack_delta = 1 + return_words
        args = args.each do |arg|
          arg = arg.split(' ').map { |a| get_var(a) || a }.join(' ')
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
          instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # push arg - #{original}", self)
        end
        instruction = "copy 0.reg #{label}.disp 0.reg"
        instructions << Instruction.new(@label_generator, instruction, "  #{instruction} # call - #{original}", self)
        if return_words > 0
          update_variable(stack, return_words)
        end
        instructions
      end
    end
  end
end

module MicroCisc
  module Compile
    class Instruction
      attr_reader :label, :instruction, :data, :imm, :sign, :dir, :reg, :dest, :original, :minimal

      def initialize(label_generator, minimal, original, sugar)
        @label_generator = label_generator
        @original = original
        @label = nil
        @operation = nil
        @sign = nil
        @dir = nil
        @imm = nil
        @src = nil
        @dest = nil
        @sugar = sugar
        parse_ucisc(minimal)
      end

      def data?
        !@data.nil?
      end

      def label?
        !@label.nil?
      end

      def instruction?
        !@operation.nil?
      end

      def comment?
        !label? && !instruction?
      end

      def parse_ucisc(minimal_instruction)
        @components = minimal_instruction.split(/\s/)

        return if @components.empty?

        first = @components.first
        if first == '{'
          @label_generator.push_context
          @label = @label_generator.start_label
        elsif first == '}'
          @label = @label_generator.end_label
          @label_generator.pop_context
        else
          label = /(?<name>[^\s]+):/.match(first)
          @label = label['name'] if label
        end
        return if @label

        if @components.first == '%'
          @components.shift
          @data = @components.map do |component|
            if match = /(?<name>[^\s]+)\.(?<type>imm|disp)/.match(component)
              [match['name'], match['type']]
            else
              if component.length % 4 != 0
                raise ArgumentError, "Data segment length must be a multiple of 2-bytes"
              end
              words = []
              (0...(component.length / 4)).each do |index|
                words << ((component[index * 4, 4]).to_i(16) & 0xFFFF)
              end
              words.pack("S*")
            end
          end
          return
        end

        @opcode = parse_component(@components.first).first
        case @opcode
        when 'copy'
          parse('copy')
        when 'compute'
          parse('alu')
        end
      end

      def parse_component(component)
        parts = component.split('.')
        if /^-{0,1}[0-9A-Fa-f]+$/.match(parts.first)
          [parts.first.to_i, parts.last.downcase]
        elsif /^-{0,1}(0x){0,1}[0-9A-Fa-f]+$/.match(parts.first)
          [parts.first.to_i(16), parts.last.downcase]
        else
          [parts.first, parts.last.downcase]
        end
      end

      def validate_alu(component, current)
        raise ArgumentError, "Duplicate #{component.last} value" if current
        code = component.first
        unless code >= 0 && code < 16
          raise ArgumentError, "Value of #{component.last} must be between 0x0 and 0xF instead of #{component.first.to_s(16).upcase}"
        end
        component.first
      end

      def validate_effect(component, current)
        raise ArgumentError, "Duplicate #{component.last} value" if current
        unless (0..7).include?(component.first)
          raise ArgumentError, "Value of #{component.last} must be between 0x0 and 0x7 instead of 0x#{component.first.to_s(16).upcase}"
        end
        component.first
      end

      def validate_boolean(component, current)
        raise ArgumentError, "Duplicate #{component.last} value" if current
        if component.first == component.last
          # Was used with syntax sugar without the numeric argument
          component[0] = 1
        end
        unless (0..1).include?(component.first)
          raise ArgumentError, "Value of #{component.last} must be 0x0 or 0x1 instead of 0x#{component.first.to_s(16).upcase}"
        end
        component.first
      end

      def validate_page_dir(component, current)
        raise ArgumentError, "Duplicate #{component.last} value" if current
        if component.first > 1 || component.first < 0
          raise ArgumentError, "Invalid page direction: #{component.first}"
        end
        if (component.first == 0 && component.last != 'out') ||
            (component.first == 1 && component.last != 'in')
          raise ArgumentError, "Invalid value #{component.first} for #{component.last}"
        end
        component.first
      end

      def parse(operation)
        @operation = operation
        components = @components[1..-1]
        args = []
        imm_pos = nil
        @uses_mem_arg = false
        uses_push = false
        uses_pop = false
        @source_is_mem = false

        while components.size > 0
          to_parse = components.shift
          if(to_parse.start_with?('$'))
            raise ArgumentError, "Missing ref #{to_parse}" unless @sugar[to_parse]
            to_parse = @sugar[to_parse]
          end
          parsed = parse_component(to_parse)
          if ['val', 'reg', 'mem'].include?(parsed.last)
            @uses_mem_arg = true if parsed.last == 'mem'
            @source_is_mem = true if args.empty? && parsed.last == 'mem'
            args << parsed
          elsif parsed.last == 'op'
            @alu_code = validate_alu(parsed, @alu_code)
          elsif parsed.last == 'push'
            @inc = validate_boolean(parsed, @sign)
            uses_push = true
          elsif parsed.last == 'pop'
            @inc = validate_boolean(parsed, @sign)
            uses_pop = true
          elsif parsed.last == 'eff'
            @eff = validate_effect(parsed, @eff)
          elsif (parsed.last == 'disp' || parsed.last == 'imm')
            raise ArgumentError, "Duplicate immediate value" if @imm
            if args.empty?
              # if immediate is first arg, this is a 4.val source
              args << [4, 'val']
            end
            if parsed.first.is_a?(Numeric)
              @imm = parsed.first
            else
              if parsed.first == 'break'
                @imm = [@label_generator.end_label, parsed.last]
              elsif parsed.first == 'loop'
                @imm = [@label_generator.start_label, parsed.last]
              else
                @imm = parsed
              end
            end
            imm_pos = args.size
            if imm_pos > 2
              raise ArgumentError, "Immediate must be part of the source argument"
            end
          else
            raise ArgumentError, "Invalid argument for #{@operation}: #{to_parse}"
          end
        end

        if args.size != 2
          raise ArgumentError, "Missing source and/or destination arguments"
        end
        @eff ||= 3
        @imm ||= 0
        if @inc && !@uses_mem_arg
          raise ArgumentError, "Memory argument required to use push and pop"
        end
        @inc ||= 0
        @bit_width = 7
        @bit_width -= 4 if @operation == 'alu'
        @bit_width -= 1 if @uses_mem_arg
        if @imm.is_a?(Numeric)
          validate_immediate(@imm)
        end

        @src, @dest, @dir = validate_args(args.first, args.last, imm_pos)
        nil
      end

      def validate_immediate(value)
        if @source_is_mem
          min = 0
          max = (2 << @bit_width) - 1
        else
          magnitude = 2 << (@bit_width - 1)
          min = magnitude * -1
          max = magnitude - 1
        end
        if (value < min || value > max)
          signed = @source_is_mem ? 'unsigned' : 'signed'
          raise ArgumentError, "Immediate max bits is #{@bit_width} #{signed}; value must be between #{min} and #{max} instead of #{value}"
        end
      end

      def encoded(label_dictionary = nil, current_address = nil)
        if @imm.is_a?(Numeric)
          imm = @imm
        elsif label_dictionary.nil?
          imm = 0
        elsif @imm.is_a?(Array)
          raise ArgumentError, 'Current address is missing' if current_address.nil?
          label_address = label_dictionary[@imm.first]
          raise ArgumentError, "Missing label '#{@imm.first}'" if label_address.nil?
          label_address = label_address & 0xFFFF
          if @imm.last == 'disp'
            imm = label_address - current_address
          elsif @imm.last == 'imm'
            imm = label_address & 0xFFFF
          else
            raise ArgumentError, "Invalid immediate spec: 0x#{@imm.first.to_s(16).upcase}.#{@imm.last}"
          end
          validate_immediate(imm)
        end

        op_code = @operation == 'alu' ? 1 : 0
        msb = (op_code << 7) | (@eff << 5) | (@dest << 2) | (@src >> 1)
        lsb = ((@src & 0x01) << 7)

        if @uses_mem_arg
          lsb = lsb | (@inc << 6)
        end

        imm_mask = ~(-1 << @bit_width)
        if @operation == 'alu'
          lsb = lsb | ((imm & imm_mask) << 4) | (@alu_code & 0xF)
        else
          lsb = lsb | (imm & imm_mask)
        end

        ((msb & 0xFF) << 8) | (lsb & 0xFF)
      end

      def validate_args(first_arg, second_arg, imm_pos)
        register = validate_reg(first_arg)
        dest = validate_dest(second_arg)

        if !imm_pos.nil? && imm_pos != 1
          raise ArgumentError, "Invalid immediate position, it must follow the first arg"
        end

        [register, dest, dir]
      end

      def validate_reg(arg)
        valid = arg.first == 0 && arg.last == 'reg'
        valid = valid || ([1, 2, 3].include?(arg.first) && arg.last == 'mem')
        valid = valid || (arg.first == 4 && arg.last == 'val')
        valid = valid || ([1, 2, 3].include?(arg.first) && arg.last == 'reg')

        if valid
          reg = arg.first
          reg += 4 if [1, 2, 3].include?(arg.first) && 'reg' == arg.last
          reg
        else
          raise ArgumentError, "Invalid register: #{arg.first.to_s}.#{arg.last}"
        end
      end

      def validate_dest(arg)
        valid = arg.last == 'mem' && [1, 2, 3].include?(arg.first)
        valid = valid || (arg.last == 'reg' && [0, 4, 1, 2, 3].include?(arg.first))

        if valid
          reg = arg.first
          reg += 4 if [1, 2, 3].include?(arg.first) && arg.last == 'reg'
          reg
        else
          raise ArgumentError, "Invalid destination: #{arg.first.to_s}.#{arg.last}"
        end
      end
    end
  end
end


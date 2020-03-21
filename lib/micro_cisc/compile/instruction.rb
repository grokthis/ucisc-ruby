module MicroCisc
  module Compile
    class Instruction
      attr_reader :label, :instruction, :data, :imm, :sign, :dir, :reg, :dest, :original, :minimal

      def initialize(label_generator, minimal, original)
        @label_generator = label_generator
        @original = original
        @label = nil
        @operation = nil
        @sign = nil
        @dir = nil
        @imm = nil
        @reg = nil
        @dest = nil
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
          hex = @components.join
          if hex.length % 4 != 0
            raise ArgumentError, "Data segment has an odd number of hex value, byte data incomplete"
          end
          bytes = []
          (0...(hex.length / 2)).each do |index|
            bytes << ((hex[index * 2, 2]).to_i(16) & 0xFF)
          end
          @data = bytes.pack("C*")
          return
        end

        @opcode = parse_component(@components.first).first
        case @opcode
        when 0x0
          @sign = 1 # Immediate is automatically signed
          parse('copy')
        when 0x7
          parse('control')
        when 0xC
          parse('page')
        when 0x200..0x21F
          @alu_code = @opcode & 0x1F
          @opcode = 0x2
          parse('alu')
        end
      end

      def parse_component(component)
        parts = component.split('.')
        if /^-{0,1}(0x){0,1}[0-9A-Fa-f]+$/.match(parts.first)
          [parts.first.to_i(16), parts.last.downcase]
        else
          [parts.first, parts.last.downcase]
        end
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
        unless (0..1).include?(component.first)
          raise ArgumentError, "Value of #{component.last} must be 0x0 or 0x1 instead of 0x#{component.first.to_s(16).upcase}"
        end
        component.first
      end

      def parse(operation)
        @operation = operation
        components = @components[1..-1]
        args = []
        imm_pos = nil

        while components.size > 0
          to_parse = components.shift
          parsed = parse_component(to_parse)
          if ['val', 'reg', 'mem'].include?(parsed.last)
            args << parsed
          elsif parsed.last == 'sign' && ['alu'].include?(@operation)
            @sign = validate_boolean(parsed, @sign)
          elsif parsed.last == 'inc' && ['alu'].include?(@operation)
            @inc = validate_boolean(parsed, @inc)
          elsif parsed.last == 'push' && ['copy'].include?(@operation)
            @inc = validate_boolean(parsed, @inc)
          elsif parsed.last == 'eff' && ['alu', 'copy'].include?(@operation)
            @eff = validate_effect(parsed, @eff)
          elsif (parsed.last == 'disp' || parsed.last == 'imm') && ['copy'].include?(@operation)
            raise ArgumentError, "Duplicate immediate value" if @imm
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
            if imm_pos < 1 || imm_pos > 2
              raise ArgumentError, "Immediate must be immediately after the register argument"
            end
          else
            raise ArgumentError, "Invalid argument for #{@operation}: #{to_parse}"
          end
        end

        if args.size != 2
          raise ArgumentError, "Missing source and/or destination arguments"
        end
        @sign ||= 0
        @eff ||= 3
        @inc ||= 0
        @imm ||= 0
        if @operation == 'alu'
          if (@inc == 1 || @sign == 0) && @eff > 3
            raise ArgumentError, "Effect must be 0-3 when 1.inc or 0.sign is specified"
          elsif @inc == 0 && @sign == 1 && @eff < 4
            raise ArgumentError, "Effect must be 4-7 when 0.inc and 0.sign is specified"
          end
        end
        if @imm.is_a?(Numeric)
          validate_immediate(@imm, args.first.first)
        end

        @reg, @dest, @dir = validate_args(args.first, args.last, imm_pos)
        nil
      end

      def validate_immediate(value, reg)
        if @operation == 'copy'
          if reg == 4 && (value < -32 || value > 31)
            raise ArgumentError, "Immediate for copy must be between -32 and 31 instead of 0x#{value}"
          elsif reg != 4 && (value < -64 || value > 63)
            raise ArgumentError, "Immediate for copy must be between -64 and 63 instead of 0x#{value}"
          end
        elsif (@sign.nil? || @sign == 0) && (value < 0x00 || value > 0xFF)
          raise ArgumentError, "Immediate must be between 0x00 and 0xFF instead of 0x#{value.to_s(16).upcase}"
        elsif @sign == 1 && (value < -256 || value > 254)
          raise ArgumentError, "Immediate must be between -256 and 254 instead of 0x#{value}"
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
            imm = label_address & 0xFF
          else
            raise ArgumentError, "Invalid immediate spec: 0x#{@imm.first.to_s(16).upcase}.#{@imm.last}"
          end
          validate_immediate(imm, @reg)
        elsif ['copy'].include?(@operation)
          raise ArgumentError, "Unexpected immediate: #{@imm}"
        end

        if @operation == 'copy'
          # 0EEDDDRR RMIIIIII
          if [1, 2, 3].include?(@reg)
            imm = imm & 0x3F
          else
            imm = imm & 0x7F
          end
          msb = (@eff << 5) | (@dest << 2) | (@reg >> 1)
          ((msb & 0xFF) << 8) | ((@reg & 0x01) << 7) | (@inc << 6) | imm
        elsif @operation == 'alu'
          # 10SMDDRR RAAAAAEE
          msb = 0x80 | (@sign << 5) | (@inc << 4) | (@dest << 2) | (@reg >> 1)
          lsb = ((@reg & 0x01) << 7) | (@alu_code << 2) | @eff % 4
          ((msb & 0xFF) << 8) | (lsb & 0xFF)
        end
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
        valid = false
        if @operation == 'alu'
          valid = arg.first == 0 && arg.last == 'reg'
          valid = valid || [1, 2, 3].include?(arg.first) && arg.last == 'mem'
          valid = valid || [4, 1, 2, 3].include?(arg.first) && arg.last == 'reg'
        elsif @operation == 'copy'
          valid = arg.first == 0 && arg.last == 'reg'
          valid = valid || [1, 2, 3].include?(arg.first) && arg.last == 'mem'
          valid = valid || arg.first == 4 && arg.last == 'val'
          valid = valid || [1, 2, 3].include?(arg.first) && arg.last == 'reg'
        end

        if valid
          reg = arg.first
          reg += 4 if [1, 2, 3].include?(arg.first) && arg.last == 'reg'
          reg
        else
          raise ArgumentError, "Invalid register value: 0x#{arg.first.to_s(16).upcase}.#{arg.last}"
        end
      end

      def validate_dest(arg)
        if @operation == 'copy'
          valid = arg.last == 'mem' && [1, 2, 3].include?(arg.first)
          valid = valid || arg.last == 'reg' && [0, 4, 1, 2, 3].include?(arg.first)
        elsif @operation == 'alu'
          valid = arg.last == 'mem' && [1, 2, 3].include?(arg.first)
          valid = valid || arg.last == 'reg' && arg.first == 0
        end
        if valid
          reg = arg.first
          reg += 4 if [1, 2, 3].include?(arg.first) && arg.last == 'reg'
          reg
        else
          raise ArgumentError, "Invalid destination value: 0x#{arg.first.to_s(16).upcase}.#{arg.last}"
        end
      end
    end
  end
end


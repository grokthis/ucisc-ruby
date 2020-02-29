module MicroCisc
  module Vm
    class InstructionParser

      attr_reader :label, :instruction, :data, :imm, :sign, :dir, :reg, :dest, :original, :minimal

      def initialize(instruction)
        @label = nil
        @operation = nil
        @sign = nil
        @dir = nil
        @imm = nil
        @reg = nil
        @dest = nil
        @original = instruction
        @minimal = filter_comments(instruction)
        parse_ucisc(@minimal)
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

      def parse_ucisc(minimal_instruction)
        @components = minimal_instruction.split(/\s/)

        return if @components.empty?

        label = /(?<name>[^\s]+):/.match(@components.first)
        if label
          @label = label['name']
          return
        end

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
          parse('copy')
        when 0x7
          parse('control')
        when 0xC
          parse('page')
        when 0xD
          @sign = 1 # Immediate is automatically signed
          parse('move')
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
        unless (0..3).include?(component.first)
          raise ArgumentError, "Value of #{component.last} must be between 0x0 and 0x3 instead of 0x#{component.first.to_s(16).upcase}"
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
          elsif parsed.last == 'sign' && ['copy', 'alu'].include?(@operation)
            @sign = validate_boolean(parsed, @sign)
          elsif parsed.last == 'inc' && ['alu'].include?(@operation)
            @inc = validate_boolean(parsed, @inc)
          elsif parsed.last == 'eff' && ['alu'].include?(@operation)
            @eff = validate_effect(parsed, @eff)
          elsif (parsed.last == 'disp' || parsed.last == 'imm') && ['copy', 'move'].include?(@operation)
            raise ArgumentError, "Duplicate immediate value" if @imm
            if parsed.first.is_a?(Numeric)
              @imm = parsed.first
            else
              @imm = parsed
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
        if @sign.nil? && ['copy', 'alu'].include?(@operation)
          raise ArgumentError, "Missing sign argument"
        end
        if @imm.nil? && ['copy', 'move'].include?(@operation)
          raise ArgumentError, "Missing immediate argument"
        end
        if @operation == 'alu'
          if @inc.nil?
            raise ArgumentError, "Missing increment argument"
          end
          if @eff.nil?
            raise ArgumentError, "Missing effect argument"
          end
          if (@inc == 1 || @sign == 0) && @eff > 3
            raise ArgumentError, "Effect must be 0-3 when 1.inc or 0.sign is specified"
          elsif @inc == 0 && @sign == 1 && @eff < 4
            raise ArgumentError, "Effect must be 4-7 when 0.inc and 0.sign is specified"
          end
        end
        if @imm.is_a?(Numeric)
          validate_immediate(@imm)
        end

        @reg, @dest, @dir = validate_args(args.first, args.last, imm_pos)
        nil
      end

      def validate_immediate(value)
        if (@sign.nil? || @sign == 0) && (value < 0x00 || value > 0xFF)
          raise ArgumentError, "Immediate must be between 0x00 and 0xFF instead of 0x#{value.to_s(16).upcase}"
        elsif @sign == 1 && (value < -128 || value > 127)
          raise ArgumentError, "Immediate must be between -128 and 127 instead of 0x#{value}"
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
          validate_immediate(imm)
        elsif ['move', 'copy'].include?(@operation)
          raise ArgumentError, "Unexpected immediate: #{@imm}"
        end

        if @operation == 'copy'
          # 0SNDDRRR IIIIIIII
          msb = (@sign << 6) | (@dir << 5) | (@dest << 3) | @reg
          ((msb & 0xFF) << 8) | (imm & 0xFF)
        elsif @operation == 'move'
          # 1101DDRR IIIIIIII
          msb = 0xD0 | (@dest << 2) | @reg
          ((msb & 0xFF) << 8) | (imm & 0xFF)
        elsif @operation == 'alu'
          # 10SDDRRR MAAAAAEE
          msb = 0x80 | (@sign << 5) | (@dest << 3) | @reg
          lsb = (@inc << 7) | (@alu_code << 2) | @eff % 4
          ((msb & 0xFF) << 8) | (lsb & 0xFF)
        end
      end

      def validate_args(first_arg, second_arg, imm_pos)
        register = nil
        dest = nil

        if @operation == 'move'
          dir = 0
          register = validate_reg(first_arg, true)
          dest = validate_dest(second_arg, false)
        elsif @operation == 'alu'
          if first_arg.last == 'val' || second_arg.first > 3
            dir = 1
            register = validate_reg(second_arg, false)
            dest = validate_dest(first_arg, true)
          else
            dir = 0
            register = validate_reg(first_arg, true)
            dest = validate_dest(second_arg, false)
          end
        elsif @operation == 'copy'
          if imm_pos == 1
            dir = 0
            register = validate_reg(first_arg, true)
            dest = validate_dest(second_arg, false)
          elsif imm_pos == 2
            dir = 1
            register = validate_reg(second_arg, false)
            dest = validate_dest(first_arg, true)
          else
            raise ArgumentError, "Invalid immediate position"
          end
        else
          raise ArgumentError, "Unsupported operation: #{@operation}"
        end

        [register, dest, dir]
      end

      def validate_reg(arg, source)
        valid = false
        if @operation == 'move'
          valid = [0, 1, 2, 3].include?(arg.first) && arg.last == 'reg'
        elsif @operation == 'alu'
          if !source
            raise ArgumentError, "ALU operations must use a reg arg as the source."
          end
          valid = arg.first == 0 && arg.last == 'reg'
          valid = valid || [1, 2, 3].include?(arg.first) && arg.last == 'mem'
          valid = valid || [4, 5, 6, 7].include?(arg.first) && arg.last == 'reg'
        elsif @operation == 'copy'
          valid = arg.first == 0 && arg.last == 'reg'
          valid = valid || [1, 2, 3].include?(arg.first) && arg.last == 'mem'
          valid = valid || source && arg.first == 4 && arg.last == 'val'
          valid = valid || !source && arg.first == 4 && arg.last == 'reg'
          valid = valid || [5, 6, 7].include?(arg.first) && arg.last == 'reg'
        end

        if valid
          arg.first
        else
          raise ArgumentError, "Invalid register value: 0x#{arg.first.to_s(16).upcase}.#{arg.last}"
        end
      end

      def validate_dest(arg, source)
        if @operation == 'move'
          valid = (arg.last == 'reg' && [0, 1, 2, 3].include?(arg.first))
        else
          valid = source && arg.first == 0 && arg.last == 'val'
          valid = valid || !source && arg.first == 0 && arg.last == 'reg'
          valid = valid || (arg.last == 'mem' && [1, 2, 3].include?(arg.first))
        end
        if valid
          arg.first
        else
          raise ArgumentError, "Invalid destination value: 0x#{arg.first.to_s(16).upcase}.#{arg.last}"
        end
      end

      def flags
        @registers[4]
      end

      def flags=(value)
        @registers[4] = value
      end

      def pc
        @registers[0]
      end

      def pc=(value)
        @registers[0] = value
      end

      def run
        instruction = load(@pc).unpack("C*")

        code = instruciton[0]
        
        if code & COPY_MASK == COPY_CODE
          do_copy(instruction)
        elsif code & MOVE_MASK == MOVE_CODE
          do_move(instruction)
        elsif code & ALU_MASK == ALU_CODE
          do_alu(instruction)
        elsif code & PAGE_MASK == PAGE_CODE
          do_page(instruction)
        elsif instruciton[0] & CONTROL_MASK == CONTROL_CODE
          do_control(instruction)
        else
          # Should not ever be possible to get here. Halt.
          puts "System error in decoding instruction"
          halt
        end

        self.pc
      end

      def do_copy(instruction)
        sign = instruction[0] & 0x40 > 0
        if sign
          # sign extend by repacking and unpacking as signed
          immediate = [instruction[1]].pack("C*").unpack("c*")
        else
          immediate = instruction[1]
        end

        direction = instruction[0] & 0x20 / 32
        destination = instruction[0] & 0x1C / 4
        source = instruction[0] & 0x03

        value =
          if direction == 0 && source == 0
            immediate
          elsif direction == 0
            load(@registers[source] + immediate)
          elsif destination == 0
            pc
          elsif destination == 4
            flags
          elsif destination > 4
            @registers[destination - 4]
          else
            unpack(load(@registers[destination]))
          end

        if direction == 0 && destination == 0
          self.pc = value
        elsif direction == 0 && destination == 4
          self.flags == value
        elsif direction == 0 && destination > 4
          @registers[destination - 4] = value
        elsif direction == 0
          store(@registers[destination], pack(value))
        elsif source == 0
          self.pc = value
        else
          store(@registers[source], pack(value))
        end
      end

      def do_move(instruction)
        immediate = instruction[1]

        destination = instruction[0] & 0xC / 4
        source = instruction[0] & 0x03

        value =
          if source == 0
            flags & immediate
          else
            @registers[source] + immediate
          end

        if destination == 0
          self.flags = value
        else
          @registers[destination] = value
        end
      end

      def do_alu(instruction)
        direction = instruction[0] & 0x20 / 32
        destination = instruction[0] & 0x1C / 4
        source = instruction[0] & 0x03
        increment = instruction[1] & 0x80 > 0
        alu_code = instruction[1] & 0x7C / 4
        effect = instruction[1] & 0x03

        arg1 =
          if direction == 0 && source == 0
            1
          elsif direction == 0
            load(@registers[source])
          elsif destination == 0
            pc
          elsif destination == 4
            flags
          elsif destination > 4
            @registers[destination - 4]
          else
            unpack(load(@registers[destination]))
          end

        arg2 =
          if direction == 1 && source == 0
            pc
          elsif direction == 1
            load(@registers[source])
          elsif destination == 0
            pc
          elsif destination == 4
            flags
          elsif destination > 4
            @registers[destination - 4]
          else
            unpack(load(@registers[destination]))
          end

        old_flags = flags
        store = effect >= 2 || (effect == 1 && zero_flag == 0) || (effect == 0 && zero_flag == 1)
        value = compute(alu_code, arg1, arg2)
        self.flags = old_flags if effect == 2

        if !store
          if increment && source >= 1 && source <= 3
            @registers[source] += 2
          end
          if increment && source != destination && destination >= 1 && destination <= 3
            @registers[destination] += 2
          end
          return
        end

        if direction == 0 && destination == 0
          self.pc = value
        elsif direction == 0 && destination == 4
          self.flags == value
        elsif direction == 0 && destination > 4
          @registers[destination - 4] = value
        elsif direction == 0
          store(@registers[destination], pack(value))
        elsif source == 0
          self.pc = value
        else
          store(@registers[source], pack(value))
        end
        
        if increment && source >= 1 && source <= 3
          @registers[source] += 2
        end
        if increment && source != destination && destination >= 1 && destination <= 3
          @registers[destination] += 2
        end
      end

      def compute(alu_code, arg1, arg2)
        overflow = 0
        carry = 0

        if alu_code == 0x00
          value = arg1 & arg2
        elsif alu_code == 0x01
          value = arg1 | arg2
        elsif alu_code == 0x02
          value = arg1 ^ arg2
        elsif alu_code == 0x03
          value = (arg1 & 0xFFFF) ^ 0xFFFF
        elsif alu_code == 0x04
          value = arg1 << arg2
        elsif alu_code == 0x06
          value = (arg1 & 0xFFFF) >> arg2
        elsif alu_code == 0x07
          value = arg1 >> arg2
        elsif alu_code == 0x09
          value = ((arg1 0xFF00) >> 8) | ((arg1 & 0x00FF) << 8)
        elsif alu_code == 0x0A || alu_code == 0x0B
          arg2 = arg2 * -1 if alu_code == 0x0B
          value = arg1 + arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        elsif alu_code == 0x0E || alu_code == 0x0F
          arg1, arg2 = [arg1, arg2].pack("C*").unpack("c*")
          arg2 = arg2 * -1 if alu_code == 0x0F
          value = arg1 + arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          elsif value < (0x8000 * -1)
            overflow = 1
            carry = 1
          elsif value & 0xF0000 > 0
            carry = 1
          end
          value = value & 0xFFFF
        end

        zero = value == 0
        positive = value > 0
        negative = value < 0

        flags = overflow | (carry << 1) | (zero << 2) | (positive << 3) | (negative << 4)
        self.flags = (flags & 0xFFE0) | flags
        value
      end

      def unpack(word, signed = false)
        bytes = word.unpack("C*")
        value = bytes[0] * 256 + bytes[1]
        value = value.pack("S*").unpack("s*") if signed
        value
      end
      
      def pack(value)
        [value & 0xFF00, value & 0x00FF].pack("C*")
      end

      def halt
        assert(false)
      end

      def load(local_address)
        if local_address < 0
          raise ArgumentError, "Invalid local address: #{local_address}"
        end
        if local_address < @local_mem.size - 1
          @local_mem[local_address..(local_address + 1)]
        elsif local_address == @local_mem.size - 1
          (@local_mem[local_address].unpack("C*") + [0]).pack("C*")
        end
      end

      def store(local_address, value)
        if local_address < 0
          raise ArgumentError, "Invalid local address: #{local_address}"
        end
        if packed_bytes.size != 2
          raise ArgumentError, "Invalid number of packed bytes: #{packed_bytes.size}"
        end
        @local_mem[local_address] = packed_bytes[0]
        if local_address < @local_mem.size - 1
          @local_mem[local_address + 1] = packed_bytes[1]
        end
      end

      def write_page(page_address, bytes)
        if page_address < 0 || page_address > 255
          raise ArgumentError, "Invalid page address: #{page_address}, expect 0 <= page address <= 255"
        end
        if bytes.size != 256
          raise ArgumentError, "Page must be 256 bytes"
        end
        start = page_address * 256
        finish = start + 256
        @local_mem[start..finish] = bytes
      end

      def read_page(page_address)
        if page_address < 0 || page_address > 255
          raise ArgumentError, "Invalid page address: #{page_address}, expect 0 <= page address <= 255"
        end
        start = page_address * 256
        finish = start + 256
        @local_mem[start..finish]
      end
    end
  end
end


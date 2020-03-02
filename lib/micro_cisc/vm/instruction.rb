module MicroCisc
  module Vm
    class Instruction

      COPY_MASK = 0x80
      MOVE_MASK = 0xF0
      ALU_MASK = 0xC0
      PAGE_MASK = 0xF0
      CONTROL_MASK = 0xE0
     
      COPY_CODE = 0x00
      MOVE_CODE = 0xD0
      ALU_CODE = 0x80
      PAGE_CODE = 0xC0
      CONTROL_CODE = 0xE0

      attr_reader :processor

      def initialize(processor, instruction)
        @processor = processor
        if instruction.is_a?(Numeric)
          @instruction = instruction & 0xFFFF
        elsif /^(0x){0,1}[0-9A-Fa-f]{4}$/.match(instruction.to_s)
          @instruction = instruction.to_i(16)
        else
          raise ArgumentError, "Invalid instruction: #{instruction}"
        end
        @pc_modified = false
        @instruction = [@instruction].pack("S>*").unpack("C*")
      end

      def pc_modified?
        @pc_modified
      end

      def to_s
        "0x#{@instruction.pack("C*").unpack("S>*").first.to_s(16).upcase}"
      end

      def exec
        @pc_modified = false
        msb = @instruction[0]

        if msb & COPY_MASK == COPY_CODE
          do_copy
        elsif msb & MOVE_MASK == MOVE_CODE
          do_move
        elsif msb & ALU_MASK == ALU_CODE
          do_alu
        elsif msb & PAGE_MASK == PAGE_CODE
          do_page
        elsif msb & CONTROL_MASK == CONTROL_CODE
          do_control
        else
          # Should not ever be possible to get here. Halt.
          puts "System error in decoding instruction"
          halt
        end
      end

      def do_copy
        msb = @instruction[0]
        lsb = @instruction[1]

        destination = (msb & 0x1C) >> 2
        source = ((msb & 0x03) << 1) | (lsb >> 7)
        effect = (msb & 0x60) >> 5
        increment = (lsb & 0x40) >> 6 == 1
        shift = source == 4 ? 0 : 1

        if lsb & 0x20 > 0
          # negative 6 digit value, with inferred 7th digit (0)
          # sign extend by repacking and unpacking as signed
          immediate = [(lsb & 0x3F | 0xC0) << shift].pack("C*").unpack("c*").first
        else
          # positive value
          immediate = (lsb & 0x3F) << shift
        end

        store =
          effect == 3 ||
          (effect == 2 && zero_flag == 0 && negative_flag == 0) ||
          (effect == 1 && zero_flag == 0) ||
          (effect == 0 && zero_flag == 1)

        increment == store && increment
        value =
          if source == 0
            processor.pc + immediate
          elsif source < 4
            unpack(load(processor.register(source) + immediate))
          elsif source == 4
            immediate
          elsif source > 4
            processor.register(source - 4) + immediate
          end

        if store
          if destination == 0
            processor.pc = value
            @pc_modified = true
          elsif destination < 4
            processor.set_register(destination, processor.register(destination) - 2) if increment
            store(processor.register(destination), pack(value))
          elsif destination == 4
            processor.flags
          elsif destination > 4
            processor.set_register(destination - 4, value)
          end
          if increment && source != destination && [1, 2, 3].include?(source)
            processor.set_register(source, processor.register(source) - 2)
          end
        end
        "0x0 R: #{source}, D: #{destination}, E: #{effect}, M: #{increment}, I: #{immediate}, value: #{value}, #{'skipping ' if !store}store"
      end

      def do_move
        msb = @instruction[0]

        destination = (msb & 0xC) / 4
        source = msb & 0x03
        shift = source == 4 ? 0 : 1
        immediate = [@instruction[1] << shift].pack("C").unpack("c").first

        value =
          if source == 0
            (processor.pc & 0xFF00) | immediate
          else
            processor.register(source) + immediate
          end

        if destination == 0
          processor.pc = value
          @pc_modified = true
        else
          processor.set_register(destination, value)
        end
        "0xD D: #{destination}, R: #{source}, IMM: #{immediate}, value: #{value}"
      end

      def do_alu
        msb = @instruction[0]
        lsb = @instruction[1]

        sign = (msb & 0x20) / 32
        destination = (msb & 0x18) / 8
        source = msb & 0x07
        increment = (lsb & 0x80) > 0
        alu_code = (lsb & 0x7C) / 4
        effect = lsb & 0x03

        arg1 =
          if source == 0
            processor.pc
          elsif source < 4
            unpack(load(processor.register(source)))
          elsif source == 4
            processor.flags
          else
            processor.register(source - 4)
          end

        arg2 =
          if destination == 0
            processor.pc
          else
            unpack(load(processor.register(destination)))
          end

        store =
          if increment || sign == 0
            effect == 3 ||
              (effect == 1 && zero_flag == 0) ||
              (effect == 0 && zero_flag == 1)
          else
            (effect == 4 && negative_flag == 0) ||
              (effect == 5 && negative_flag == 1) ||
              (effect == 6 && overflow_flag == 0)
          end
        value = compute(alu_code, arg1, arg2)
        if !store
          return "0x2#{'%02x' % [alu_code]} R: #{source}, D: #{destination}, Sign: #{sign}, Inc: #{increment}, Eff: #{effect}, value: #{value}, skipping store"
        end

        if destination == 0
          processor.pc = value
          @pc_modified = true
        elsif destination == 4
          processor.flags == value
        elsif destination > 4
          processor.set_register(destination - 4, value)
        else
          store(processor.register(destination), pack(value))
        end
        
        increment(source, sign) if increment
        increment(destination, sign) if increment && source != destination
        "0x2#{'%02x' % [alu_code]} R: #{source}, D: #{destination}, Sign: #{sign}, Inc: #{increment}, Eff: #{effect}, value: #{value}, stored"
      end

      def increment(r, sign)
        return if r < 1 || r > 3
        delta = sign ? -2 : 2
        processor.set_register(r, processor.register(r) + delta)
      end

      def overflow_flag
        processor.flags & 0x01
      end

      def carry_flag
        (processor.flags >> 3) & 0x01
      end

      def negative_flag
        (processor.flags >> 3) & 0x01
      end

      def zero_flag
        (processor.flags >> 2) & 0x01
      end

      def compute(alu_code, arg1, arg2)
        overflow = 0
        carry = 0

        if alu_code == 0x00
          value = arg1
        elsif alu_code == 0x01
          value = arg2 & arg1
        elsif alu_code == 0x02
          value = arg2 | arg1
        elsif alu_code == 0x03
          value = arg2 ^ arg1
        elsif alu_code == 0x04
          value = (arg1 & 0xFFFF) ^ 0xFFFF
        elsif alu_code == 0x05
          # parity
          value = arg1.to_s(2).map { |d| d if d == '1' }.compact.size
        elsif alu_code == 0x06
          value = arg2 << arg1
        elsif alu_code == 0x07
          value = (arg2 & 0xFFFF) >> arg1
        elsif alu_code == 0x08
          value = arg2 >> arg1
        elsif alu_code == 0x09
          value = ((arg1 0xFF00) >> 8) | ((arg1 & 0x00FF) << 8)
        elsif alu_code == 0x0A || alu_code == 0x0C
          arg1 = arg1 * -1 if alu_code == 0x0C
          value = arg2 + arg1
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        elsif alu_code == 0x0B || alu_code == 0x0D
          arg1, arg2 = [arg1, arg2].pack("C*").unpack("c*")
          arg1 = arg1 * -1 if alu_code == 0x0D
          value = arg2 + arg1
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
        elsif alu_code == 0x0E
          value = arg1 * arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        elsif alu_code == 0x10
          value = arg1 / arg2
          value = value & 0xFFFF
        elsif alu_code == 0x12
          value = arg1 % arg2
          value = value & 0xFFFF
        end

        zero = value == 0 ? 1 : 0
        positive = value > 0 ? 1 : 0
        negative = value < 0 ? 1 : 0

        flags = overflow | (carry << 1) | (zero << 2) | (negative << 3)
        processor.flags = (flags & 0xFFE0) | flags
        value
      end

      def unpack(word, signed = false)
        bytes = word.unpack("C*")
        value = bytes[0] * 256 + bytes[1]
        value = value.pack("S*").unpack("s*") if signed
        value
      end
      
      def pack(value)
        [(value & 0xFF00) >> 8, value & 0x00FF].pack("C*")
      end

      def halt
        assert(false)
      end

      def load(local_address)
        processor.load(local_address)
      end

      def store(local_address, value)
        processor.store(local_address, value)
      end
    end
  end
end


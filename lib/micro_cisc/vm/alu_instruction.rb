module MicroCisc
  module Vm
    class AluInstruction
      def self.exec(processor, word)
        # 10SMDDRR RAAAAAEE
        sign = (word & 0x2000) > 0
        increment = (word & 0x1000) > 0
        source = (word & 0x0380) >> 7
        destination = (word & 0x0C00) >> 10
        alu_code = (word & 0x007C) >> 2
        flags = processor.flags
        value = compute(
          processor,
          alu_code,
          arg1(processor, word, source, destination, increment, sign),
          arg2(processor, word, destination)
        )

        return 0 unless store?(flags, word, increment, sign)

        # Detect debug/break instruction
        if source == 0 && destination == 0 && alu_code == 0 && !increment
          2
        else
          store(processor, word, source, destination, value, increment, sign)
          0
        end
      end

      def self.store?(flags, word, increment, sign)
        effect = (word & 0x0003)
        if !increment && sign
          effect += 4
        end
        return true if effect == 3
        return false if effect == 7

        zero = flags & 0x04 > 0
        return true if (effect == 0 && zero) || (effect == 1 && !zero)

        negative = flags & 0x08 > 0
        overflow = flags & 0x01 > 0

        (effect == 2 && !zero && !negative) ||
        (effect == 4 && !negative) ||
        (effect == 5 && negative) ||
        (effect == 6 && !overflow)
      end

      def self.arg1(processor, word, source, destination, increment, sign)
        value =
          if source == 0
            processor.pc
          elsif source < 4
            processor.load(processor.register(source))
          elsif source == 4
            processor.flags
          elsif source > 4
            processor.register(source - 4)
          end
        value
      end

      def self.arg2(processor, word, destination)
        if destination == 0
          processor.pc
        else
          processor.load(processor.register(destination))
        end
      end

      def self.store(processor, word, source, destination, value, increment, sign)
        if destination == 0
          processor.pc = value
        else
          processor.store(processor.register(destination), value)
        end
        if increment
          increment(processor, source, sign)
          increment(processor, destination, sign) if source != destination
        end
      end

      def self.compute(processor, alu_code, arg1, arg2, update_flags = true)
        overflow = 0
        carry = 0

        case alu_code
        when 0x00
          value = arg1
        when 0x01
          value = arg2 & arg1
        when 0x02
          value = arg2 | arg1
        when 0x03
          value = arg2 ^ arg1
        when 0x04
          value = (arg1 & 0xFFFF) ^ 0xFFFF
        when 0x05
          value = arg2 << arg1
        when 0x06
          value = (arg2 & 0xFFFF) >> arg1
        when 0x07
          value = arg2 >> arg1
        when 0x08
          value = arg1 % arg2
          value = value & 0xFFFF
        when 0x09
          arg1, arg2 = [arg1, arg2].pack("S*").unpack("s*")
          value = arg1 % arg2
          value = value & 0xFFFF
        when 0x0A,0x0C
          arg1 = arg1 * -1 if alu_code == 0x0C
          value = arg2 + arg1
          if value > 0xFFFF || value < 0
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        when 0x0B,0x0D
          arg1, arg2 = [arg1, arg2].pack("S*").unpack("s*")
          arg1 = arg1 * -1 if alu_code == 0x0D
          value = arg2 + arg1
          carry = value & 0x10000 >> 16
          overflow = 1 if (arg1 & 0x8000) == (arg2 & 0x8000) && (value & 0x8000) != (arg2 & 0x8000)
          value = value & 0xFFFF
        when 0x0E
          value = arg1 * arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        when 0x0F
          arg1, arg2 = [arg1, arg2].pack("S*").unpack("s*")
          value = arg1 * arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        when 0x10
          value = arg1 / arg2
          value = value & 0xFFFF
        when 0x11
          arg1, arg2 = [arg1, arg2].pack("S*").unpack("s*")
          value = arg1 / arg2
          value = value & 0xFFFF
        when 0x12
          value = ((arg1 & 0xFF00) >> 8) | ((arg1 & 0x00FF) << 8)
        when 0x13
          value = arg1 >> 8
        when 0x14
          value = arg1 & 0xFF00
        when 0x15
          value = arg1 & 0x00FF
        when 0x16
          value = (arg1 & 0xFF00) | (arg2 & 0x00FF)
        when 0x17
          value = (arg1 & 0x00FF) | (arg2 & 0xFF00)
        when 0x18
          value = ((arg1 & 0x00FF) << 8) | (arg2 & 0x00FF)
        when 0x19
          value = (arg1 >> 8) | (arg2 & 0xFF00)
        else
          raise ArgumentError, "Unsupported ALU code #{alu_code.to_s(16).upcase}"
        end

        zero = value == 0 ? 1 : 0
        negative = (value & 0x8000) > 0 ? 1 : 0

        flags = overflow | (carry << 1) | (zero << 2) | (negative << 3)
        processor.flags = flags if update_flags
        value
      end

      def self.increment(processor, r, sign)
        return if r < 1 || r > 3
        delta = sign ? -1 : 1
        processor.set_register(r, processor.register(r) + delta)
      end

      def self.ucisc(processor, word)
        source = (word & 0x0380) >> 7
        src =
          if source == 0
            '0.reg'
          elsif source < 4
            "#{source}.mem"
          elsif source == 4
            '4.reg'
          else
            "#{source - 4}.reg"
          end

        destination = (word & 0x0C00) >> 10
        dest =
          if destination == 0
            '0.reg'
          else
            "#{destination}.mem"
          end

        sign = (word & 0x2000) > 0
        increment = (word & 0x1000) > 0
        effect = (word & 0x0003)
        if increment && sign == 1
          effect += 4
        end

        store = store?(processor.flags, word, increment, sign)
        alu_code = (word & 0x007C) >> 2
        _1 = arg1(processor, word, source, destination, increment, sign)
        _2 = arg2(processor, word, destination)
        value = compute(processor, alu_code, _1, _2, false)

        inc = "#{increment ? 1 : 0}.inc"
        sign = "#{sign ? 1 : 0}.sign"
        eff = "#{effect}.eff"
        alu_code = '%02x' % [alu_code]
        comment = "# arg1: #{_1}, arg2: #{_2}, result #{value}, #{'not ' if !store}stored"
        "0x2#{alu_code} #{src} #{dest} #{inc} #{sign} #{eff} #{comment}"
      end
    end
  end
end

module MicroCisc
  module Vm
    # For performance reasons the instruction classes are not instantiated
    # on each clock cycle and we just execute the instruction using static methods
    # Performance isn't a deal breaker, but 0.75 MIPS seems much better than 0.1 MIPS
    # We just want something reasonable, actual hardware will leave this in the dust.
    class AluInstruction
      def self.exec(processor, word)
        # 10SMDDRR RAAAAAEE
        sign = (word & 0x2000) > 0
        increment = (word & 0x1000) > 0
        source = (word & 0x0380) >> 7
        destination = (word & 0x0C00) >> 10
        value = result(
          processor,
          word,
          arg1(processor, word, source, destination, increment, sign),
          arg2(processor, word, destination)
        )
        return false unless store?(processor.flags, word, increment, sign)
        store(processor, word, source, destination, value, increment, sign)

        destination == 0 && value == 0 
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

      def self.result(processor, word, arg1, arg2)
        alu_code = (word & 0x007C) >> 2
        compute(processor, alu_code, arg1, arg2)
      end

      def self.store(processor, word, source, destination, value, increment, sign)
        if destination == 0
          processor.pc = result
        else
          processor.store(processor.register(destination), value)
        end
        if increment
          increment(processor, source, sign)
          increment(processor, destination, sign) if source != destination
        end
      end

      def self.compute(processor, alu_code, arg1, arg2)
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
          # parity
          value = arg1.to_s(2).map { |d| d if d == '1' }.compact.size
        when 0x06
          value = arg2 << arg1
        when 0x07
          value = (arg2 & 0xFFFF) >> arg1
        when 0x08
          value = arg2 >> arg1
        when 0x09
          value = ((arg1 0xFF00) >> 8) | ((arg1 & 0x00FF) << 8)
        when 0x0A,0x0C
          arg1 = arg1 * -1 if alu_code == 0x0C
          value = arg2 + arg1
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        when 0x0B,0x0D
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
        when 0x0E
          value = arg1 * arg2
          if value > 0xFFFF
            overflow = 1
            carry = 1
          end
          value = value & 0xFFFF
        when 0x10
          value = arg1 / arg2
          value = value & 0xFFFF
        when 0x12
          value = arg1 % arg2
          value = value & 0xFFFF
        else
          raise ArgumentError, "Unsupported ALU code #{alu_code.to_s(16).upcase}"
        end

        zero = value == 0 ? 1 : 0
        positive = value > 0 ? 1 : 0
        negative = value < 0 ? 1 : 0

        flags = overflow | (carry << 1) | (zero << 2) | (negative << 3)
        processor.flags = flags
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
        inc = "#{increment ? 1 : 0}.inc"
        sign = "#{sign ? 1 : 0}.sign"
        eff = "#{effect}.eff"
        alu_code = '%02x' % [(word & 0x007C) >> 2]

        _1 = arg1(processor, word, source, destination, increment, sign)
        _2 = arg2(processor, word, destination)

        value = result(processor, word, _1, _2)
        comment = "# arg1: #{_1}, arg2: #{_2}, result #{value}, #{'not ' if !store}stored"
        "0x2#{alu_code} #{src} #{dest} #{inc} #{sign} #{eff} #{comment}"
      end

    end
  end
end

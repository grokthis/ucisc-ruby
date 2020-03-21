module MicroCisc
  module Vm
    # For performance reasons the instruction classes are not instantiated
    # on each clock cycle and we just execute the instruction using static methods
    # Performance isn't a deal breaker, but 0.75 MIPS seems much better than 0.1 MIPS
    # We just want something reasonable, actual hardware will leave this in the dust.
    class CopyInstruction
      def self.exec(processor, word)
        # 0EEDDDRR RCIIIIII
        return false unless store?(processor.flags, word)

        destination = (word & 0x1C00) >> 10
        value = source_value(processor, word, destination)
        store(processor, word, value, destination)

        destination == 0 && value == 0 
      end

      def self.store?(flags, word)
        effect = (word & 0x6000)
        return true if effect == 0x6000

        zero = flags & 0x04 > 0
        effect = effect >> 13
        return true if (effect == 0 && zero) || (effect == 1 && !zero)

        negative = flags & 0x08 > 0
        effect == 2 && !zero && !negative
      end

      def self.source_value(processor, word, destination)
        if destination > 0 && destination < 4
          # 6 digit value, memory target
          immediate = (word & 0x3F)
          # Fancy bit inverse for high performance sign extend
          immediate = ~(~(immediate & 0x3F) & 0x3F) if (word & 0x20) > 0
        else
          # 7 digit value, register target, C is imm value
          immediate = (word & 0x7F)
          # Fancy bit inverse for high performance sign extend
          immediate = ~(~(immediate & 0x7F) & 0x7F) if (word & 0x40) > 0
        end

        source = (word & 0x0380) >> 7
        case source
        when 0
          processor.pc + immediate
        when 1,2,3
          processor.load(processor.register(source) + immediate)
        when 4
          immediate
        else
          processor.register(source - 4) + immediate
        end
      end

      def self.store(processor, word, value, destination)
        case destination
        when 0
          processor.pc = value
        when 1,2,3
          address = processor.register(destination)
          if (word & 0x40) > 0
            address = (address - 1) & 0xFFFF
            processor.set_register(destination, address)
          end
          processor.store(address, value)
        when 4
          processor.flags
        else
          processor.set_register(destination - 4, value)
        end
      end

      def self.ucisc(processor, word)
        source = (word & 0x0380) >> 7
        src =
          if source == 0
            '0.reg'
          elsif source < 4
            "#{source}.mem"
          elsif source == 4
            '4.val'
          else
            "#{source - 4}.reg"
          end

        destination = (word & 0x1C00) >> 10
        dest =
          if destination == 0
            '0.reg'
          elsif destination < 4
            "#{destination}.mem"
          elsif destination == 4
            '4.reg'
          else
            "#{destination - 4}.reg"
          end

        dest_memory = destination >= 1 && destination <= 3

        if dest_memory
          # Sign extend 6 digit value, memory target
          sign = (word & 0x20) > 0 ? 0xC0 : 0x00
          imm = [(word & 0x3F) | sign].pack("C*").unpack("c*").first
        else
          # Sign extend 7 digit value, register target, C is imm value
          sign = (word & 0x40) > 0 ? 0x80 : 0x00
          imm = [(word & 0x7F) | sign].pack("C*").unpack("c*").first
        end
        imm = imm < 0 ? "-0x#{(imm * -1).to_s(16).upcase}" : "0x#{imm.to_s(16)}"
        effect = (word & 0x6000) >> 13
        eff = "#{effect}.eff"
        push = (word & 0x40) >> 6 == 1
        push = "#{push ? 1 : 0}.push"

        value = source_value(processor, word, destination)
        store = store?(processor.flags, word)
        "0x0 #{src} #{imm} #{dest} #{eff} #{push} # value: #{value}, #{'not ' if !store}stored"
      end
    end
  end
end

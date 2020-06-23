module MicroCisc
  module Vm
    # Many of the coding decisions made in here are for performance reasons:
    #
    # 1. Mostly one big class, avoiding object creation and referencing
    # 2. More verbose programming style in some cases
    # 3. Optimized/strange bitwise math for performance/avoiding ruby magic
    # 4. Some strange branching structures to shortcut common paths
    # 5. Few accessor methods, prefer instance vars
    # 6. Little runtime error checking
    #
    # Performance isn't a deal breaker, but 1+ MIPS, roughly speaking, gives me a few
    # times the MIPS of an original 6502 which puts me in the ball park of where I
    # need to be to do some real programming. We just want something reasonable for
    # debuging and doing some real coding, actual hardware will leave this in the
    # dust most likely.
    class Processor < Device
      OP_MASK             = 0x8000
      EFFECT_MASK         = 0x6000
      DESTINATION_MASK    = 0x1C00
      SOURCE_MASK         = 0x0380
      ALU_OP_MASK         = 0x000F
      IMMEDIATE_MASK      = 0x0030
      INCREMENT_MASK      = 0x0040
      IMMEDIATE_SIGN_MASK = 0x0020

      OP_SHIFT            = 15
      EFFECT_SHIFT        = 13
      DESTINATION_SHIFT   = 10
      SOURCE_SHIFT        = 7

      NEGATIVE_MASK       = 0x0004
      ZERO_MASK           = 0x0002
      OVERFLOW_MASK       = 0x0001

      SIGNED_MODE_FLAG    = 0x0100
      HALT_MODE_FLAG      = 0x0200

      SIGN_BIT            = 0x8000
      PAGE_MASK           = 0xFFC0

      MEM_ARGS            = [1, 2, 3]

      attr_accessor :flags, :pc, :overflow, :control, :debug

      def initialize(id, local_blocks, rom_blocks = [])
        super(id, 1, local_blocks, rom_blocks)

        @registers = [0, 0, 0, 0]
        @pc = 0
        @flags = 0
        @overflow = 0
        @debug = false
        @run = false
      end

      def handle_control_update(address, value)
        if address == 0x7
          self.pc = value
        elsif address == 0x8
          set_register(1, value)
        elsif address == 0x9
          set_register(2, value)
        elsif address == 0xA
          set_register(3, value)
        elsif address == 0xB
          @flags = value & 0xFFFF
        elsif address == 0xC
          self.control = value
        end
      end

      def control=(value)
        @control = value & 0xFFFF
      end

      def pc=(value)
        @pc_modified = true
        @pc = value & 0xFFFF
      end

      def register(id)
        @registers[id]
      end

      def set_register(id, value)
        @registers[id] = value
      end

      def extract_immediate(word, is_copy, inc_is_immediate, signed)
        if is_copy
          immediate_mask = IMMEDIATE_MASK | ALU_OP_MASK
          immediate_shift = 0
        else
          immediate_mask = IMMEDIATE_MASK
          immediate_shift = 4
        end

        sign_mask = IMMEDIATE_SIGN_MASK
        if inc_is_immediate
          sign_mask = INCREMENT_MASK
          immediate_mask = immediate_mask | INCREMENT_MASK
        end

        if signed && ((word & sign_mask) != 0)
          # Fancy bit inverse for high performance sign extend
          ~(~(word & immediate_mask) & immediate_mask) >> immediate_shift
        else
          (word & immediate_mask) >> immediate_shift
        end
      end

      def store?(flags, effect)
        return true if effect == 3 # handle the common case quickly

        zero = flags & ZERO_MASK != 0
        (effect == 0 && zero) ||
          (effect == 1 && !zero) ||
          (effect == 2 && flags & OVERFLOW_MASK != 0)
      end

      def source_value(source, immediate)
        case source
        when 0
          @pc + immediate
        when 1,2,3
          read_mem(@id, @registers[source] + immediate)
        when 4
          immediate
        else
          @registers[source - 4] + immediate
        end
      end

      def destination_value(destination)
        case destination
        when 0
          @pc
        when 1,2,3
          read_mem(@id, @registers[destination])
        when 4
          @control
        else
          @registers[destination - 4]
        end
      end

      def exec_instruction(word)
        source = (word & SOURCE_MASK) >> SOURCE_SHIFT
        destination = (word & DESTINATION_MASK) >> DESTINATION_SHIFT
        effect = (word & EFFECT_MASK) >> EFFECT_SHIFT

        signed = !MEM_ARGS.include?(source)
        inc_is_immediate = signed && !MEM_ARGS.include?(destination)
        is_copy = word & OP_MASK == 0
        immediate = extract_immediate(word, is_copy, inc_is_immediate, signed)

        alu = word & ALU_OP_MASK
        result = compute_result(is_copy, source, destination, immediate, alu, true)

        return false unless store?(@flags, effect)

        push = !inc_is_immediate && (word & INCREMENT_MASK) > 0
        store_result(result, source, destination, push, 0)

        # Detect halt instruction
        return 1 if immediate == 0 && source == 0 && destination == 0
        0
      end

      def compute_result(is_copy, source, destination, immediate, alu, update_flags)
        source_value = source_value(source, immediate)
        if is_copy
          source_value
        else
          destination_value = destination_value(destination)
          compute(alu, source_value, destination_value, update_flags)
        end
      end

      def store_result(value, source, destination, push, sign)
        case destination
        when 0
          @pc = value
          @pc_modified = true
        when 1,2,3
          if push
            @registers[destination] = (@registers[destination] - 1) & 0xFFFF
          end
          address = @registers[destination]
          write_mem(@id, @registers[destination], value)
        when 4
          self.control = value
        else
          @registers[destination - 4] = value
        end
        if push && !MEM_ARGS.include?(destination) && MEM_ARGS.include?(source)
          @registers[source] = (@registers[source] + 1) & 0xFFFF
        end
      end

      def compute(alu_code, arg1, arg2, update_flags)
        overflow = 0
        overflow_reg = 0

        case alu_code
        when 0x00
          # INV
          value = (arg1 & 0xFFFF) ^ 0xFFFF
        when 0x01
          # AND
          value = arg2 & arg1
        when 0x02
          # OR
          value = arg2 | arg1
        when 0x03
          # XOR
          value = arg2 ^ arg1
        when 0x04
          # Negate (2's compliment)
          value = -1 * arg1
        when 0x05
          # Shift left, zero extend
          value = arg2 << arg1
          overflow_reg = (value & 0xFFFF0000) >> 16
          value = value & 0xFFFF
        when 0x06
          # Shift right, repsect signed mode
          overflow_mask = ~(-1 << arg1) & 0xFFFF
          overflow_reg = arg2 & overflow_mask
          overflow_reg >> (arg1 - 16) if arg1 > 16

          if @control & SIGNED_MODE_FLAG == 0
            value = (arg2 & 0xFFFF) >> arg1
          else
            value = arg2 >> arg1
          end
        when 0x07
          # Swap MSB and LSB bytes
          value = ((arg1 & 0xFF00) >> 8) | ((arg1 & 0x00FF) << 8)
        when 0x08
          # Zero LSB
          value = arg1 & 0xFF00
        when 0x09
          # Zero MSB
          value = arg1 & 0x00FF
        when 0x0A,0x0B
          arg1 = (arg1 ^ 0xFFFF) + 1 if alu_code == 0x0B
          value = (arg1 & 0xFFFF) + (arg2 & 0xFFFF)
          # Add, respect signed mode
          if @control & SIGNED_MODE_FLAG == 0
            if value > 0xFFFF
              overflow = 1
              overflow_reg = 1
            end
          else
            if ((arg1 & SIGN_BIT) == (arg2 & SIGN_BIT)) &&
                ((arg1 & SIGN_BIT) != (value & SIGN_BIT))
              overflow = 1
              overflow_reg = (value & 0xFFFF0000 >> 16) & 0xFFFF
            end
          end
          value = value & 0xFFFF
        when 0x0C
          if @control & SIGNED_MODE_FLAG == 0
            arg1 = ~(~arg1 & 0xFFFF) if arg1 & SIGN_BIT != 0
            arg2 = ~(~arg2 & 0xFFFF) if arg2 & SIGN_BIT != 0
          end
          value = arg1 * arg2
          overflow_reg = (value & 0xFFFF0000 >> 16) & 0xFFFF
          if ((overflow_reg & SIGN_BIT) == (value_reg & SIGN_BIT)) &&
              overflow_reg == 0xFFFF
            # There was no actual overflow, it's just the sign extension
            overflow = 0 
          else
            overflow = 1
          end
          value = value & 0xFFFF
        when 0x0D
          if @control & SIGNED_MODE_FLAG == 0
            arg1 = ~(~arg1 & 0xFFFF) if arg1 & SIGN_BIT != 0
            arg2 = ~(~arg2 & 0xFFFF) if arg2 & SIGN_BIT != 0
          end
          value = arg2 / arg1
          overflow_reg = arg2 % arg1
          value = value & 0xFFFF
        when 0x0E
          value = arg1 & PAGE_MASK
        when 0x0F
          value = arg1 + @overflow
        else
          raise ArgumentError, "Unsupported ALU code #{alu_code.to_s(16).upcase}"
        end

        zero = value == 0 ? 1 : 0
        negative = (value & 0x8000) == 0 ? 0 : 1

        if update_flags
          flags =
            (overflow * OVERFLOW_MASK) |
            (zero * ZERO_MASK) |
            (negative * NEGATIVE_MASK)
          @flags = flags
          @overflow = overflow_reg
        end
        value
      end

      def start(debug = false)
        @debug = debug
        @run = true
        run
      end

      def run
        @t0 = Time.now
        count = 0
        while(@run) do
          word = read_mem(@id, @pc, true)
          if @debug
            # Pause before executing next command
            do_command("#{'%04x' % [@pc]} #{ucisc(word)} ")
          end
          special = exec_instruction(word)
          if special != 0
            halt(count) if special == 1
            @debug = true if special == 2
          end
          if @pc_modified
            @pc_modified = false
          else
            @pc += 1
          end
          count += 1
          # if count & 0xFF == 0
          #   read_from_processor
          # end
        end
      end

      def do_command(prefix = '')
        return unless @debug
        $stdout.print "#{prefix}> "
        command = $stdin.readline
        exit(1) if /exit/.match(command)
        @debug = true if /debug|n|next/.match(command)
        @debug = false if /c|continue/.match(command)
        byebug if /break/.match(command)
      end

      def format_data(data)
        data.map { |w| '%04x' % w }.join(' ').gsub(/(([0-9A-Za-z]{4} ){16})/, "\\1\n")
      end

      def halt(count)
        delta = (Time.now - @t0)
        puts("HALT: #{count} instructions in #{delta}s")

        @run = false
      end

      def ucisc(word)
        source = (word & SOURCE_MASK) >> SOURCE_SHIFT
        destination = (word & DESTINATION_MASK) >> DESTINATION_SHIFT
        effect = (word & EFFECT_MASK) >> EFFECT_SHIFT

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

        signed = !MEM_ARGS.include?(source)
        inc_is_immediate = signed && !MEM_ARGS.include?(destination)
        is_copy = word & OP_MASK == 0
        immediate = extract_immediate(word, is_copy, inc_is_immediate, signed)

        value = source_value(source, immediate)
        store = store?(@flags, effect)

        alu = word & ALU_OP_MASK
        result = compute_result(is_copy, source, destination, immediate, alu, true)
        alu = is_copy ? '' : "0x#{alu.to_s(16).upcase}.op "

        imm = immediate < 0 ? "-#{(immediate * -1)}" : "#{immediate.to_s}"
        eff = "#{effect}.eff"
        push = !inc_is_immediate && (word & INCREMENT_MASK) > 0
        push = push ? 'push ' : ''
        ins = is_copy ? 'copy' : 'compute'

        "#{ins} #{alu}#{src} #{imm} #{dest} #{eff} #{push}# value: #{value} (0x#{'%04x' % value}), result: #{result} (0x#{'%04x' % result}), #{'not ' if !store}stored"
      end

      private

      def read_from_processor
        return unless @system_reader.ready?
        message = Message.read_from_stream(@system_reader)
        return if message.nil?

        if message.write?
          page = message.local_page & 0xFF
          data = message.data
          write_page(page, data)
          @paging = @paging.select { |p| p != page }
        elsif message.start?
          @run = true
        elsif message.halt?
          halt
        end
      end
    end
  end
end

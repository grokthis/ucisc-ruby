module MicroCisc
  module Vm
    # Many of the coding decisions made in the Vm classes are for performance reasons:
    #
    # 1. Static instruction classes, less object oriented encapsulation
    # 2. More verbose programming style
    # 3. Optimized/strange bitwise math
    # 4. Some strange branching structures to shortcut common paths
    # 5. Few accessor methods
    # 6. Little runtime error checking
    #
    # Performance isn't a deal breaker, but 0.94 MIPS seems much better than the
    # 0.11 MIPS I was getting before (on my 7 year old MacBook Pro). Roughly speaking
    # that gives me about 2x the MIPS of an original 6502 which puts me in the ball
    # park of where I need to be to do some real programming. We just want something
    # reasonable for debuging and doing some real coding, actual hardware will leave
    # this in the dust as the FPGAs I'm eyeing will be 100x or more.
    class Processor
      OPCODES = [
        CopyInstruction,
        CopyInstruction,
        AluInstruction,
        nil
      ]

      attr_accessor :flags, :pc, :debug

      def initialize(device_id = 0, mem_bytes = nil)
        @device_id = device_id
        @local_mem = Array.new(65536).map { 0 }
        if !mem_bytes.nil?
          max = [65535, mem_bytes.size].min
          @local_mem[0..max] = mem_bytes[0..max]
        end
        @registers = [0, 0, 0, 0]
        @pc = 0
        @flags = 0
        @debug = false
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

      def run
        word = load(@pc)
        directive = OPCODES[(word & 0xC000) >> 14]
        puts 'Starting program... (enter to continue)'
        do_command("#{'%04x' % [@pc]} #{directive.ucisc(self, word)} ")
        t0 = Time.now
        count = 0
        while(true) do
          count += 1
          word = load(@pc)
          directive = OPCODES[(word & 0xC000) >> 14]
          do_break = directive.exec(self, word)
          if @pc_modified
            @pc_modified = false
          else
            @pc += 1
          end
          if do_break || @debug
            if @pc == 0 && count > 1
              delta = (Time.now - t0)
              puts "Breaking on jump to 0x0000..."
              puts "Finished #{count} instructions in #{delta}s"
              count = 0
            end
            # Pause before executing next command
            word = load(@pc)
            directive = OPCODES[(word & 0xC000) >> 14]
            do_command("#{'%04x' % [@pc]} #{directive.ucisc(self, load(@pc))} ")
            t0 = Time.now
          end
        end
      end

      def do_command(prefix = '')
        $stdout.print "#{prefix}> "
        command = $stdin.readline
        exit(1) if /exit/.match(command)
        byebug if /break/.match(command)
        @debug = true if /debug|n|next/.match(command)
        @debug = false if /c|continue/.match(command)
      end

      def load(local_address)
        @local_mem[local_address]
      end

      def store(local_address, value)
        @local_mem[local_address] = value
      end

      def write_page(page_address, words)
        if page_address < 0 || page_address > 255
          raise ArgumentError, "Invalid page address: #{page_address}, expect 0 <= page address <= 255"
        end
        if words.size != 256
          raise ArgumentError, "Page must be 256 bytes"
        end
        start = page_address * 256
        finish = start + 256
        @local_mem[start..finish] = words
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

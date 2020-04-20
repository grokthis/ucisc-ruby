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
        CopyInstruction,
        CopyInstruction,
        AluInstruction,
        AluInstruction,
        PageInstruction,
        nil
      ]

      attr_accessor :flags, :pc, :debug

      def initialize(system_writer, system_reader)
        @system_writer = system_writer
        @system_reader = system_reader

        @local_mem = Array.new(256).map{ Array.new(256).map { 0 } }
        @registers = [0, 0, 0, 0]
        @pc = 0
        @flags = 0
        @debug = false
        @run = false
        @paging = []
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
        @t0 = Time.now
        count = 0
        while(@run) do
          if @debug
            # Pause before executing next command
            word = load(@pc)
            directive = OPCODES[(word & 0xE000) >> 13]
            do_command("#{'%04x' % [@pc]} #{directive.ucisc(self, load(@pc))} ")
          end
          word = load(@pc)
          special = OPCODES[(word & 0xE000) >> 13].exec(self, word)
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
          if count & 0xFF == 0
            read_from_processor
          end
        end
      end

      def log_message(message)
        msg = Message.new
        msg.log_message(message)
        msg.write_to_stream(@system_writer)
      end

      def do_command(prefix = '')
        return unless @debug
        $stdout.print "#{prefix}> "
        command = $stdin.readline
        exit(1) if /exit/.match(command)
        byebug if /break/.match(command)
        @debug = true if /debug|n|next/.match(command)
        @debug = false if /c|continue/.match(command)
      end

      def load(local_address)
        page = local_address >> 8
        if @paging.size > 0
          while(@paging.include?(page))
            read_from_processor
          end
        end
        @local_mem[page][local_address % 256]
      end

      def store(local_address, value)
        page = local_address >> 8
        if @paging.size > 0
          while(@paging.include?(page))
            read_from_processor
          end 
        end
        @local_mem[page][local_address % 256] = value
      end

      def page_in(main, local, lock)
        local = local & 0xFF
        @paging << local
        msg = Message.new
        msg.request_page(main, local, lock)
        #puts "Page in: #{local} <- #{main}"
        msg.write_to_stream(@system_writer)
      end

      def page_out(main, local, lock)
        data = @local_mem[local]
        msg = Message.new
        msg.write(main, local, data, lock)
        #puts "Page out: #{local} -> #{main} data:\n#{format_data(data)}"
        msg.write_to_stream(@system_writer)
      end

      def format_data(data)
        data.map { |w| '%04x' % w }.join(' ').gsub(/(([0-9A-Za-z]{4} ){16})/, "\\1\n")
      end

      def write_page(page, words)
        if page < 0 || page > 255
          raise ArgumentError, "Invalid page address: #{page}, expect 0 <= page address <= 255"
        end
        if words.size != 256
          raise ArgumentError, "Page must be 256 bytes"
        end
        @local_mem[page] = words
      end

      def read_page(page)
        if page < 0 || page > 255
          raise ArgumentError, "Invalid page address: #{page}, expect 0 <= page address <= 255"
        end
        @local_mem[page]
      end

      def start
        while(true) do
          if @run
            run
          else
            read_from_processor
          end
        end
      rescue Interrupt
      end

      def halt(count)
        delta = (Time.now - @t0)
        log_message("HALT: #{count} instructions in #{delta}s")

        @run = false
        msg = Message.new
        msg.halt
        msg.write_to_stream(@system_writer)
      end

      private

      def read_from_processor
        return unless @system_reader.ready?
        message = Message.read_from_stream(@system_reader)
        exit if message.nil?

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

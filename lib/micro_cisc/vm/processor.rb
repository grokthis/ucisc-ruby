module MicroCisc
  module Vm
    class Processor

      COPY_MASK = 0x80
      MOVE_MASK = 0xF0
      ALU_MASK = 0xE0
      PAGE_MASK = 0xF0
      CONTROL_MASK = 0xE0
     
      COPY_CODE = 0x00
      MOVE_CODE = 0xD0
      ALU_CODE = 0x80
      PAGE_CODE = 0xC0
      CONTROL_CODE = 0xE0

      def initialize(device_id = 0, mem_bytes = nil)
        @device_id = device_id
        @local_mem = Array.new(65536).map { 0 }.pack("C*")
        if !mem_bytes.nil?
          max = [65535, mem_bytes.size].min
          @local_mem[0..max] = mem_bytes[0..max]
        end
        @registers = [0, 0, 0, 0, 0]
      end

      def flags
        @registers[4]
      end

      def flags=(value)
        @registers[4] = value & 0xFFFF
      end

      def pc
        @registers[0]
      end

      def pc=(value)
        @registers[0] = value & 0xFFFF
      end

      def register(id)
        @registers[id]
      end

      def set_register(id, value)
        @registers[id] = value & 0xFFFF
      end

      def run(debug = false)
        t0 = Time.now
        count = 0
        while(true) do
          count += 1
          instruction = load(pc).unpack("S*").first
          instruction = Instruction.new(self, instruction)
          before = self.pc
          result = instruction.exec
          if debug
            byebug if do_command("#{'%04x' % [before]} #{result} ")
          end
          if instruction.pc_modified? && self.pc == 0
            delta = (Time.now - t0)
            puts "Jump 0x000 detected..."
            puts "Finished #{count} instructions in #{delta}s"
            count = 0
            byebug if do_command
          end
          self.pc += 2 unless instruction.pc_modified?
        end
      end

      def do_command(prefix = '')
        $stdout.print "#{prefix}> "
        command = $stdin.readline
        exit(1) if /exit/.match(command)
        true if /break/.match(command)
      end

      def load(local_address)
        if local_address < 0 || local_address > 65535
          raise ArgumentError, "Invalid local address: #{local_address}"
        end
        if local_address < @local_mem.size - 1
          @local_mem[local_address..(local_address + 1)]
        elsif local_address == @local_mem.size - 1
          (@local_mem[local_address].unpack("C*") + [0]).pack("C*")
        end
      end

      def store(local_address, value)
        if local_address < 0 || local_address > 65535
          raise ArgumentError, "Invalid local address: #{local_address}"
        end
        @local_mem[local_address..(local_address + 1)] = value
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


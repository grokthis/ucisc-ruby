module MicroCisc
  module Vm
    class Message
      attr_accessor :processor_id, :instruction, :local_page, :main_page,
        :registers, :pc, :flags, :data, :memory, :message, :lock

      def initialize(content = nil)
        @content = content

        parse_content(content) if content
      end

      def write_to_stream(stream)
        data = serialize
        stream.write([data.size].pack("L"))
        stream.write(data)
      end

      def self.read_from_stream(stream)
        length = stream.read(4)
        return nil unless length
        length = length.unpack("L").first
        Message.new(stream.read(length))
      end

      def parse_content(content)
        i = 0
        while i < content.length
          field = content[i]
          i += 1
          case field
          when 'i'
            length = content[i...(i + 4)].unpack("L").first
            i += 4
            @instruction = content[i...(i + length)]
            i += length
          when 'l'
            @local_page = content[i...(i + 2)].unpack("S").first
            i += 2
          when 'm'
            @main_page = content[i...(i + 4)].unpack("L").first
            i += 4
          when 'r'
            @registers = content[i...(i + 8)].unpack("S*")
            i += 8
          when 'p'
            @pc = content[i...(i + 2)].unpack("S").first
            i += 2
          when 'f'
            @flags = content[i...(i + 2)].unpack("S").first
            i += 2
          when 'd'
            length = content[i...(i + 4)].unpack("L").first * 2
            i += 4
            @data = content[i...(i + length)].unpack("S*")
            i += length
          when 'e'
            length = content[i...(i + 4)].unpack("L").first * 2
            i += 4
            @memory = content[i...(i + length)].unpack("S*")
            i += length
          when 's'
            length = content[i...(i + 4)].unpack("L").first
            i += 4
            @message = content[i...(i + length)]
            i += length
          when 'k'
            @lock = content[i...(i + 1)].unpack("C").first == 1
            i += 1
          end
        end
      end

      def serialize
        serial = []
        descriptor = ''
        if @instruction
          serial << 'i'
          serial << @instruction.size
          serial += @instruction.chars
          descriptor += 'aL' + ('a' * @instruction.size)
        end
        if @local_page
          serial << 'l'
          serial << @local_page
          descriptor += 'aS'
        end
        if @main_page
          serial << 'm'
          serial << @main_page
          descriptor += 'aL'
        end
        if @registers
          serial << 'r'
          serial += @registers
          descriptor += 'aSSSS'
        end
        if @pc
          serial << 'p'
          serial << @pc
          descriptor += 'aS'
        end
        if @flags
          serial << 'f'
          serial << @flags
          descriptor += 'aS'
        end
        if @data
          serial << 'd'
          serial << @data.size
          serial += @data
          descriptor += 'aL' + ('S' * @data.size)
        end
        if @memory
          serial << 'e'
          serial << @memory.size
          serial += @memory
          descriptor += 'aL' + ('S' * @memory.size)
        end
        if @message
          serial << 's'
          serial << @message.size
          serial += @message.chars
          descriptor += 'aL' + ('a' * @message.size)
        end
        if @lock
          serial << 'k'
          serial << (@lock ? 1 : 0)
          descriptor += 'ac'
        end
        serial.pack(descriptor)
      end

      def lock?
        @lock == true
      end

      def halt?
        @instruction == 'halt'
      end

      def write?
        @instruction == 'write'
      end

      def request_page?
        @instruction == 'request_page'
      end

      def log_message?
        @instruction == 'log'
      end

      def break?
        @instruction == 'break'
      end

      def start?
        @instruction == 'start'
      end

      def next?
        @instruction == 'next'
      end

      def request_state?
        @instruction == 'request_state'
      end

      def state?
        @instruction == 'state'
      end

      def start
        @instruction = 'start'
      end

      def halt
        @instruction = 'halt'
      end

      def write(main_page, local_page, word_array, lock = false)
        @instruction = 'write'
        @local_page = local_page
        @main_page = main_page
        @data = word_array
        @lock = lock
      end

      def request_page(main_page, local_page, lock)
        @instruction = 'request_page'
        @local_page = local_page
        @main_page = main_page
        @lock = lock
      end

      def log_message(message)
        @instruction = 'log'
        @message = message
      end

      def break
        @instruction = 'break'
      end

      def next
        @instruction = 'next'
      end

      def request_state
        @instruction = 'request_state'
      end

      def send_state(pc, registers, flags, memory)
        @instruction = 'state'
        @pc = pc
        @registers = registers
        @flags = flags
        @memory = memory
      end
    end
  end
end

module MicroCisc
  module Vm
    class TermDevice < Device
      def initialize(device_id)
        super(device_id, 9, 1)
        # Init device specific read/write controls
        @privileged_read = @privileged_read | 0xE0
        @privileged_write = @privileged_write | 0x20
      end

      def host_device=(device_id)
        @control_mem[2] = device_id
      end

      def handle_control_read(address)
        case(address)
        when 7
          @control_mem[7] = TTY::Screen.width
        when 8
          @control_mem[8] = TTY::Screen.height
        end
      end

      def handle_control_update(address, value)
        if address == 5
          # value is number of bytes to send
          words = (value + 1) / 2
          string = @local_mem[0][0...words].pack("S>*")[0...value]
          $stdout.write(string)
          $stdout.flush
        end
      end
    end
  end
end

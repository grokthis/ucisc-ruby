module MicroCisc
  module Vm
    class TermDevice < Device
      def initialize(device_id)
        super(device_id, Device::TYPE_TERMINAL, 1)
        # Init device specific read/write controls
        @privileged_read = @privileged_read | 0x1C0
        @privileged_write = @privileged_write | 0x40
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
        if address == 6
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

module MicroCisc
  module Vm
    # This is a generic device base class providing memory and control access
    #
    # From the docs, the control word layout is as follows:
    #
    # * 0x0 - Device ID - read only. Unique system wide.
    # * 0x1 - Local bank block (MSB) | Device type (LSB) - read only
    # * 0x2 - Init device ID - read only if set, writable if 0 or by init device
    # * 0x3 - Accessed device block address (LSB) - writable by init device
    # * 0x4 - <Reserved> (MSB) | Device status (LSB)
    # * 0x5 - Local register with interrupt handler address (read/write)
    # * 0x6 to 0xF - Device type specific (see below)
    class Device
      TYPE_INVALID = 0
      TYPE_PROCESSOR = 1
      TYPE_BLOCK_MEMORY = 2
      TYPE_BLOCK_IO = 3
      TYPE_SERIAL = 4
      TYPE_HID = 5
      TYPE_TERMINAL = 6

      attr_reader :id

      def initialize(id, type, local_blocks, rom_blocks = [])
        @id = id
        @external_read = 0x003F
        @privileged_read = 0x003F
        @privileged_write = 0x002C
        @internal_write = 0x0010

        @local_blocks = local_blocks
        rom_blocks.each { |block| block.freeze }
        ram_blocks = Array.new(local_blocks - rom_blocks.size).map do
          Array.new(256).map { 0 }
        end
        @local_mem = rom_blocks + ram_blocks

        @control = 0
        @control_mem = Array.new(16).map { 0 }
        @control_mem[0] = id
        @control_mem[1] = type & 0xFF
        @control_mem[2] = 0

        @devices = [self]
      end

      def bank_index=(index)
        @control_mem[1] = ((index & 0xFF) << 8) | (@control_mem[1] & 0xFF)
      end

      def devices=(devices)
        @devices = [self] + devices
        @devices.each_with_index { |device, index| device.bank_index = index }
      end

      def write_control(source_device_id, address, value)
        address = address & 0xF
        return if address == 0
        if source_device_id == @id
          return if (1 << (address - 1)) & @internal_write == 0
          @control_mem[address] = value
        elsif @control_mem[2] == 0 || source_device_id == @control_mem[2]
          # Special case where a processor can "claim" the device
          @control_mem[2] = source_device_id

          return if (1 << (address - 1)) & @privileged_write == 0
          @control_mem[address] = value
          handle_control_update(address, value)
        end
      end

      def read_control(source_device_id, address)
        if address == 0
          handle_control_read(address)
          @control_mem[0]
        elsif source_device_id == @id || source_device_id == @control_mem[2]
          return 0 if (1 << (address - 1)) & @privileged_read == 0
          handle_control_read(address)
          @control_mem[address]
        else
          return 0 if (1 << (address - 1)) & @external_read == 0
          handle_control_read(address)
          @control_mem[address]
        end
      end

      def handle_control_read(address)
        # Does nothing by default, override in subclass
      end

      def handle_control_update(address, value)
        # Does nothing by default, override in subclass
      end

      def banked?(address)
        banked = ((address & 0xF000) >> 12)
        if banked == 0
          banked = 1
        else
          banked = 1 << banked
        end
        (banked & @control) != 0
      end

      def write_mem(source_device_id, address, value)
        banked = banked?(address)
        device = (address >> 4)
        if banked && source_device_id == @id && device < @devices.size
          @devices[device].write_control(source_device_id, address & 0xF, value)
        elsif banked && source_device_id == @id && device >= 256
          device = (address >> 8)
          if device < @devices.size
            @devices[device].write_mem(source_device_id, address & 0xFF, value)
          else
            page = (address & 0xFF00) >> 8
            @local_mem[page][address & 0xFF] = value
          end
        elsif !banked && source_device_id == @id
          block = (address & 0xFF00) >> 8
          @local_mem[block][address & 0xFF] = value
        elsif source_device_id == @control_mem[2]
          block = @control_mem[3]
          @local_mem[block][address & 0xFF] = value if @local_mem[block]
        end
      end

      def read_mem(source_device_id, address, force_local = false)
        banked = banked?(address) && !force_local
        device = (address >> 4)
        if banked && source_device_id == @id && device < @devices.size
          @devices[device].read_control(source_device_id, address & 0xF)
        elsif banked && source_device_id == @id && device >= 256
          device = (address >> 8)
          if device < @devices.size
            @devices[device].read_mem(source_device_id, address & 0xFF)
          else
            page = (address & 0xFF00) >> 8
            @local_mem[page][address & 0xFF]
          end
        elsif !banked && source_device_id == @id
          page = (address & 0xFF00) >> 8
          @local_mem[page][address & 0xFF]
        elsif source_device_id == @control_mem[2]
          page = @control_mem[3] & 0xFF00
          @local_mem[page][address * 0xFF]
        end
      end
    end
  end
end

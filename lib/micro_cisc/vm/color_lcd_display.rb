require 'gtk2'

module MicroCisc
  module Vm
    class ColorLcdDisplay < Device
      COLOR_MODE_12BIT = 1
      COLOR_MODE_16BIT = 2
      COLOR_MODES = [COLOR_MODE_16BIT, COLOR_MODE_12BIT].freeze

      def initialize(device_id, mem_blocks, width, height, bit_mode)
        super(device_id, Device::TYPE_BLOCK_MEMORY, mem_blocks)
        @w = width
        @h = height
        @bit_mode = COLOR_MODES.include?(bit_mode) ? bit_mode : COLOR_MODES.first
        @image_data = Array.new(@w * @h * 3).map { 0 }
        @scale =
          if @w <= 320
            4
          elsif @w <= 640
            2
          else
            1
          end
        @control_mem[6] = @w
        @control_mem[7] = @h
        @privileged_read = @privileged_read | 0x0C0

        Gtk.init

        @window = Gtk::Window.new.set_default_size(@w * @scale, @h * @scale)
        @window.set_title("uCISC Virtual Machine")
        @window.set_resizable(false)

        update_screen

        @window.signal_connect("destroy") do
          Gtk.main_quit
        end
        GLib::Timeout.add(5) do
          do_update
          true
        end
        @window.show

        @window_thread = Thread.new do
          Gtk.main
        end
      end

      def join
        @window_thread.join
      end

      def update_screen
        pixel_buffer = GdkPixbuf::Pixbuf.new(
          data: @image_data.pack("C*"),
          colorspace: GdkPixbuf::Colorspace::RGB,
          has_alpha: false,
          bits_per_sample: 8,
          width: @w,
          height: @h
        )
        pixel_buffer = pixel_buffer.scale_simple(@w * @scale, @h * @scale, 0)
        new_image = Gtk::Image.new(pixel_buffer)
        @window.remove(@image) if @image
        @window.add(new_image)
        new_image.show
        @window.show
        @image = new_image
      end

      def do_update
        @t0 ||= Time.now
        @tcount ||= 0

        update_image_data
        update_screen
 
        @tcount += 1
        if @tcount == 60
          delta = Time.now - @t0
          #puts "60 frames in #{delta}s (#{60 / delta} fps)"
          @t0 = Time.now
          @tcount = 0
        end
      rescue Interrupt
      end

      def update_image_data
        (0...@w).each do |x|
          (0...@h).each do |y|
            word_offset = y * @w + x
            pixel_offset = word_offset * 3
            word = read_mem(@id, word_offset, true)
            if (@bit_mode == COLOR_MODE_16BIT)
              r = (word & 0x0F00) >> 8
              @image_data[pixel_offset] = r + (r >> 5)
              g = (word & 0x07E0) >> 3
              @image_data[pixel_offset + 1] = g + (g >> 5)
              b = (word & 0x001F) << 3
              @image_data[pixel_offset + 2] = b + (b >> 5)
            elsif (@bit_mode == COLOR_MODE_12BIT)
              r = (word & 0x0F00) >> 4
              @image_data[pixel_offset] = r + (r >> 4)
              g = word & 0x00F0
              @image_data[pixel_offset + 1] = g + (g >> 4)
              b = (word & 0x000F) << 4
              @image_data[pixel_offset + 2] = b + (b >> 4)
            end
          end
        end
      end
    end
  end
end

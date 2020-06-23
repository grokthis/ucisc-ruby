module MicroCisc
  module Vm
    class Video
      attr_reader :config_page, :start_page, :page_count, :end_page
      def initialize(proc_count, mem_size, rom, debug = false)
        @bytes_per_pixel = 2
        @w = 640
        @h = 480
        @refresh = 24
        @page_count = (@w * @h * @bytes_per_pixel + 511) / 512
        @enabled = 1

        # Initialize the control section of main memory
        config_mem = [@enabled, @w, @h, @bytes_per_pixel, @refresh]
        config_mem = config_mem + Array.new(256 - config_mem.size).map { 0 }
        @config_page = 16
        @start_page = 17
        @end_page = @config_page + @page_count

        @reader, @writer = IO.pipe

        fork do
          @reader.close
          system = System.new(proc_count, mem_size, rom, self, debug)
          system.write_page(@config_page, config_mem)
          system.run
        end

        @writer.close
        # Initialize the video memory space
        @memory = [config_mem] + Array.new(@page_count).map { Array.new(256).map { 0 } }
        launch
      end

      def send_page_update(main_page, data)
        msg = Message.new
        msg.write(main_page, main_page - @config_page, data)
        msg.write_to_stream(@writer)
      end

      def launch
        require 'gtk2'
        
        Gtk.init

        @image_data = Array.new(@w * @h * 3).map { 0 }
        pixel_buffer = GdkPixbuf::Pixbuf.new(
          data: @image_data.pack("C*"),
          colorspace: GdkPixbuf::Colorspace::RGB,
          has_alpha: false,
          bits_per_sample: 8,
          width: 640,
          height: 480
        )
        @image = Gtk::Image.new(pixel_buffer)

        @window = Gtk::Window.new.set_default_size(640, 480)
        @window.set_title("uCISC Virtual Machine")
        @window.set_resizable(false)
        @window.add(@image)
        @image.show
        @window.signal_connect("destroy") do
          Gtk.main_quit
        end
        GLib::Timeout.add(15) do
          do_update
          true
        end
        @window.show

        Gtk.main
      end

      def do_update
        @t0 ||= Time.now
        @tcount ||= 0
        changed = false

        while(@reader.ready?) do
          msg = Message.read_from_stream(@reader)
          if msg.write?
            changed = true
            page = msg.local_page
            data = msg.data
            data = data[0...256] if data.size > 256
            @memory[page] = data

           if msg.local_page == 0
              @config_page = data
              @enabled, @w, @h, @bytes_per_pixel, @refresh = @config_page[0...4]
              @window.resize(@w, @h)
            else
              update_page(page)
            end
          else
            exit(0)
          end
        end

        if changed
          pixel_buffer = GdkPixbuf::Pixbuf.new(
            data: @image_data.pack("C*"),
            colorspace: GdkPixbuf::Colorspace::RGB,
            has_alpha: false,
            bits_per_sample: 8,
            width: 640,
            height: 480
          )
          new_image = Gtk::Image.new(pixel_buffer)
          @window.remove(@image)
          @window.add(new_image)
          new_image.show
          @window.show
          @image = new_image
        end
 
        @tcount += 1
        if @tcount == 60
          delta = Time.now - @t0
          #puts "60 frames in #{delta}s (#{60 / delta} fps)"
          @t0 = Time.now
          @tcount = 0
        end
      rescue Interrupt
      end

      def update_page(page)
        word_offset = (page - 1) * 256
        finish = word_offset + 256
        row_words = @bytes_per_pixel * @w / 2
        pixel_x = word_offset % row_words
        pixel_y = (word_offset / row_words)

        while word_offset < finish
          word = @memory[page][word_offset % 256]
          pixel_offset = (pixel_y * @w + pixel_x) * 3
          @image_data[pixel_offset] = ((word & 0xF800) >> 8) + 7
          @image_data[pixel_offset + 1] = ((word & 0x07E0) >> 3) + 3
          @image_data[pixel_offset + 2] = ((word & 0x001F) << 3) + 7

          word_offset += 1
          pixel_x += 1
          if pixel_x % @w == 0
            pixel_x = 0
            pixel_y += 1
          end
        end
      end
    end
  end
end

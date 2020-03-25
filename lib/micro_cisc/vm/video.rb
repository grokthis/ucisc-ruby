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
        require 'chunky_png'
        require 'ruby2d'
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
        @image = ChunkyPNG::Image.new(@w, @h + 2, ChunkyPNG::Color::BLACK)
        # This is a hack to make chunky output more color depth
        # Doesn't work right otherwise
        i = 0
        while(i < @w * 2)
          word = i % 65536
          r = (word & 0xF800) >> 3
          g = (word & 0x07E0) >> 2
          b = (word & 0x001F) << 3
          @image[i % @w, @h + i / @w] = ChunkyPNG::Color.rgb(r, g, b)
          i += 1
        end

        @window = Ruby2D::Window.new(
          title: 'uCISC Virtual Machine',
          width: @w,
          height: @h
        )
        page = 0
        while(page < @page_count)
          page += 1
          update_page(page)
        end
        @window.update do
          do_update
        end
        @window.show
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
              @window.set(width: @w, height: @h)
            else
              update_page(page)
            end
          else
            exit(0)
          end
        end

        if changed
          @image.save('screen.png')
          new_screen = Ruby2D::Image.new('screen.png')
          @window.add(new_screen)
          @window.remove(@screen) if @screen
          @screen = new_screen
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
          r = ((word & 0xF800) >> 8) + 7
          g = ((word & 0x07E0) >> 3) + 3
          b = ((word & 0x001F) << 3) + 7
          @image[pixel_x, pixel_y] = ChunkyPNG::Color.rgb(r, g, b)

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

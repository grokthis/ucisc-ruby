module MicroCisc
  module Vm
    class System
      def initialize(processor_count, mem_size, rom, video, debug = false)
        if rom.size % 256 > 0 || rom.size >= 4096
          raise ArgumentError, "ROM size must be a multiple of 256 and at most 4k words"
        end
        @debug = debug
        @rom = rom.each_slice(256).to_a
        mem_size = mem_size - rom.size
        @mem_start_page = @rom.size
        # mem is an array of pages. Makes swapping pages super fast
        @mem = Array.new(mem_size / 256).map { Array.new(256).map { 0 } }
        @tasks = []
        @mutex = Mutex.new
        @queue = []
        @video = video
        start_processors(processor_count)
      end

      def read_page(page)
        if page > @rom.size
          @mem[page]
        else
          @rom[page]
        end
      end

      def write_page(page, words)
        return if page < @mem_start_page
        words = words[0...256] if words.size > 256
        @mem[page] = words

        # If memory is in the video memory mapped region
        # write send it to the video system
        return if @video.nil?
        return if page < @video.config_page
        return if page > @video.end_page
        Thread.new do
          begin
            @video.send_page_update(page, words)
          rescue
            exit
          end
        end
      end

      def run
        @tasks = [ 0 ]
        while(true) do
          @processors.each do |p|
            process_processor(p)

            if @tasks.size > 0 && p[:status] == :idle
              task = @tasks.shift
              p[:status] = :busy

              puts "Starting task #{task} on processor #{p}"
              message = Message.new
              message.write(task, 0, read_page(task))
              message.write_to_stream(p[:writer])

              # Start execution
              message = Message.new
              message.start
              message.write_to_stream(p[:writer])
            end
          end
          @video.process_messages
        end
      rescue Interrupt
      end

      private

      def process_request(request)
        if request.request_page?
          word_array = read_page(request.main_page)
          response = Message.new
          response.write(
            request.main_page,
            request.local_page,
            word_array
          )
          writer = @processors[request.processor_id][:writer]
          response.write_to_stream(writer)
        elsif request.write?
          write_page(request.main_page, request.data)
        elsif request.log_message?
          puts "#{request.processor_id}: #{request.message}"
        elsif request.halt?
          @processors[request.processor_id][:status] = :idle
        end
      end

      def process_processor(process)
        return unless process[:reader].ready?

        #t0 = Time.now
        request = Message.read_from_stream(process[:reader])
        if request.nil?
          #puts "Processor terminated: #{process[:id]}"
          return
        end

        request.processor_id = process[:id]
        process_request(request)
        #puts "Processed #{request.instruction} request in #{Time.now - t0}s"
      end

      def start_processors(count)
        @processors ||= []
        count.times do
          reader_S2P, writer_S2P = IO.pipe
          reader_P2S, writer_P2S = IO.pipe

          process = {
            status: :idle,
            writer: writer_S2P,
            reader: reader_P2S,
            id: @processors.size
          }

          process[:process] = fork do
            # This is the processor process

            # Close pipes on system side
            writer_S2P.close
            reader_P2S.close

            # Create the processor and associated reader thread
            p = Processor.new(writer_P2S, reader_S2P)
            p.debug = @debug
            p.start
          end
          @processors << process
        end
      end
    end
  end
end

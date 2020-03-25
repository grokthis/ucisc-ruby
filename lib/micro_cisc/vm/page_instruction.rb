module MicroCisc
  module Vm
    class PageInstruction
      def self.exec(processor, word)
        # 110NLLPP PKIIIIII
        main = main_page(processor, word)
        local = local_page(processor, word)

        direction = (word & 0x1000) > 0
        lock = (word & 0x0040) > 0
        if direction
          processor.page_in(main, local, lock)
        else
          processor.page_out(main, local, lock)
        end
        0
      end

      def self.local_page(processor, word)
        local_page = (word & 0x0C00) >> 10

        case local_page
        when 0
          false
        else
          processor.load(processor.register(local_page))
        end
      end

      def self.main_page(processor, word)
        main_page = (word & 0x0380) >> 7

        # 6 bit value, memory target
        immediate = (word & 0x3F)
        # Fancy bit inverse for high performance sign extend
        immediate = ~(~(immediate & 0x3F) & 0x3F) if (word & 0x20) > 0

        case main_page
        when 0
          raise ArgumentError, "Main page designated by option 0 not yet supported"
        when 1,2,3
          processor.load(processor.register(main_page) + immediate)
        when 4
          immediate
        else
          xaddr = processor.load(processor.register(main_page) + immediate + 1) << 16
          xaddr = xaddr | processor.load(processor.register(main_page) + immediate)
        end
      end

      def self.ucisc(processor, word)
        main_page = (word & 0x0380) >> 7

        # 6 bit value, memory target
        imm = (word & 0x3F)
        # Fancy bit inverse for high performance sign extend
        imm = ~(~(immediate & 0x3F) & 0x3F) if (word & 0x20) > 0

        main_page_value = self.main_page(processor, word)
        mem =
          if main_page == 0
            raise ArgumentError, "Main page designated by option 0 not yet supported"
          elsif main_page < 4
            main_page_value = processor.load(processor.register(main_page))
            "#{main_page}.mem"
          elsif main_page == 4
            '4.val'
          else
            "#{main_page - 4}.xmem"
          end

        local_page_value = self.local_page(processor, word)
        local_page = (word & 0x0C00) >> 10
        local =
          if local_page == 0
            '0.blank'
          else
            "#{local_page}.mem"
          end

        imm = imm < 0 ? "-0x#{(imm * -1).to_s(16).upcase}" : "0x#{imm.to_s(16).upcase}"
        direction = (word & 0x1000) >> 12
        lock = (word & 0x0040) >> 6
        if direction == 0
          direction = '0.out'
        else
          direction = '1.in'
        end
        "0x6 #{mem} #{imm} #{local} #{direction} #{lock}.lock # local_page: #{local_page_value} main_page: #{main_page_value}"
      end
    end
  end
end

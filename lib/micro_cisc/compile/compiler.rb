module MicroCisc
  module Compile
    class Compiler
      def initialize(text)
        @text = text
        parse
      end

      def parse
        line_number = 1
        @instructions = []
        address = 0
        @labels = {}
        @sugar = {}
        errors = []
        lgen = MicroCisc::Compile::LabelGenerator.new
        @text.each_line do |line|
          begin
            statement = MicroCisc::Compile::Statement.new(lgen, line, @sugar)
            statement.parse.each do |instruction|
              if instruction.label?
                @labels[instruction.label] = address
              elsif instruction.instruction?
                @instructions << [line_number, instruction]
                address += 1
              elsif instruction.data?
                @instructions += instruction.data.map { |d| [line_number, d] }
                line_string = []
                word_counts = instruction.data.map do |d|
                  if d.is_a?(String)
                    line_string << d.unpack("S*").map { |w| '%04x' % w }.join
                    d.size / 2
                  else
                    line_string << d.join('.')
                    1 # 1 16-bit word reference
                  end
                end
                address += word_counts.sum
              end
            end
          rescue ArgumentError => e
            MicroCisc.logger.error("Error on line #{line_number}: #{e.message}\n  #{line}")
            errors << [line_number, e, line]
          end
          line_number += 1
        end

        if errors.size > 0
          errors = errors.map do |error|
            "#{error[0]}: #{error[1]}\n  #{error[2]}"
          end
          MicroCisc.logger.error("\n\nErrors found:\n\n#{errors.join("\n")}")
          exit(1)
        end
      end

      def serialize(file = nil)
        @serialize ||=
          begin
            words = []
            dstart = nil
            MicroCisc.logger.info("ADDRESS: INS-WORD  LINE#: SOURCE")
            @instructions.each do |(line_number, ins)|
              if ins.is_a?(String)
                address = words.length
                ins_words = ins.unpack("S*")
                dstart ||= address
                words += ins_words
              elsif ins.is_a?(Array)
                dstart ||= address
                # Address reference in data
                label_address = @labels[ins.first]
                if ins.last == 'disp'
                  words << label_address - address
                elsif ins.last == 'imm'
                  words << (label_address & 0xFFFF)
                end
              else
                address = words.length
                if dstart
                  MicroCisc.logger.info(" 0x#{'%04x' % dstart}: #{(address - dstart)} words of data")
                  dstart = nil
                end
                MicroCisc.logger.info(" 0x#{'%04x' % address}: 0x#{'%04x' % ins.encoded(@labels, address)}   #{'% 6d' % line_number}: " + ins.original.gsub("\n", ""))
                words << ins.encoded(@labels, address)
              end
            end
            if dstart
              address = words.length
              MicroCisc.logger.info(" 0x#{'%04x' % dstart}: #{(address - dstart)} words of data")
            end
            words
          end

        File.open(file, 'w') do |file|
          file.write(@serialize.pack("S*"))
        end if file

        @serialize
      end
    end
  end
end

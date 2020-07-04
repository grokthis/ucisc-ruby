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
                puts "#{line_number}: #{instruction.label}"
              elsif instruction.instruction?
                @instructions << instruction
                address += 1
                puts "#{line_number}: 0x#{instruction.encoded.to_s(16).upcase}" + instruction.original
              elsif instruction.data?
                @instructions += instruction.data
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
                puts "#{line_number}: 0x#{line_string.join(' ')}"
              end
            end
          rescue ArgumentError => e
            puts "Error on line #{line_number}: #{e.message}"
            puts line
            errors << [line_number, e, line]
          end
          line_number += 1
        end

        if errors.size > 0
          puts
          puts
          puts "Errors found:"
          puts
          errors.each do |error|
            puts "#{error[0]}: #{error[1]}\n  #{error[2]}"
          end
          exit(1)
        end
      end

      def serialize(file = nil)
        @serialize ||=
          begin
            words = []
            dstart = nil
            @instructions.each do |ins|
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
                  puts "#{'%04x' % dstart}-#{'%04x' % (address - 1)}: #{(address - dstart)} words of data"
                  dstart = nil
                end
                puts "#{'%04x' % address}: 0x#{'%04x' % ins.encoded(@labels, address)}" + ins.original
                words << ins.encoded(@labels, address)
              end
            end
            if dstart
              address = words.length
              puts "#{'%04x' % dstart}-#{'%04x' % (address - 1)}: #{(address - dstart)} words of data"
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

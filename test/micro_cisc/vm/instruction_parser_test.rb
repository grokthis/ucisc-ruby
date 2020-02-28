require 'test_helper'

module MicroCisc
  module Vm
    class InstructionParserTest < Minitest::Test
      def test_parse
        text = File.open("ex01.ucisc").read
        line_number = 1
        instructions = []
        labels = {}
        text.each_line do |line|
          begin
            ins = InstructionParser.new(line)
            if ins.label?
              labels[ins.label] = instructions.size * 2
              puts "#{line_number}: #{ins.label}"
            elsif ins.instruction?
              instructions << ins
              puts "#{line_number}: 0x#{ins.encoded.to_s(16).upcase}" + ins.original
            end
          rescue ArgumentError => e
            puts "Error on line #{line_number}: #{e.message}"
            puts line
          end
          line_number += 1
        end

        puts "Writing file:"
        address = 0
        instructions.each do |ins|
          puts "#{address.to_s(16).upcase}: 0x#{ins.encoded(labels, address).to_s(16).upcase}" + ins.original
          address += 2
        end
      end
    end
  end
end

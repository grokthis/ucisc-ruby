require "json"
require "io/wait"
require "tty-screen"
require 'logger'

require "micro_cisc/version"
require "micro_cisc/compile/label_generator"
require "micro_cisc/compile/instruction"
require "micro_cisc/compile/statement"
require "micro_cisc/compile/compiler"

require "micro_cisc/vm/device"
require "micro_cisc/vm/processor"
require "micro_cisc/vm/term_device"
require "micro_cisc/vm/empty_device"

module MicroCisc
  class Error < StandardError; end

  def self.load(file_name)
    text = File.read(file_name)
    MicroCisc::Compile::Compiler.new(text)
  end

  def self.run(data)
    rom = Array.new(256).map { 0 }
    rom[0...data.size] = data
    terminal = MicroCisc::Vm::TermDevice.new(5)
    terminal.host_device = 1
    devices = Array.new(16).map { MicroCisc::Vm::EmptyDevice.new }
    devices[15] = terminal # first banked device
    processor = MicroCisc::Vm::Processor.new(1, 256, [rom])
    processor.devices = devices
    processor.start(ARGV.include?('-d'))
    processor
  end

  def self.logger
    @logger ||=
      begin
        logger = Logger.new(STDOUT)
        logger.formatter = proc do |severity, datetime, progname, msg|
          "#{severity}: #{msg}\n"
        end
        logger
      end
  end
end

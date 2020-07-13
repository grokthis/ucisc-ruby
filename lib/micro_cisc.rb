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
require "micro_cisc/vm/color_lcd_display"

module MicroCisc
  class Error < StandardError; end

  def self.load(file_names)
    text = ""
    file_names.each do |file_name|
      text += File.read(file_name)
    end
    MicroCisc::Compile::Compiler.new(text)
  end

  def self.run(data)
    blocks = data.size / 256 + 1
    rom_blocks = []
    (0...blocks).each do |block|
      rom = Array.new(256).map { 0 }
      size = data.size - block * 256
      size = 256 if size > 256
      rom[0...size] = data[(block * 256)...((block + 1) * 256)]
      rom_blocks << rom
    end
    terminal = MicroCisc::Vm::TermDevice.new(5)
    screen = MicroCisc::Vm::EmptyDevice.new
    init_screen = ARGV.include?('-s')
    if(init_screen)
      screen = MicroCisc::Vm::ColorLcdDisplay.new(
        6, # Device ID
        40, # 10k words of memory (40 blocks)
        128, # screen pixel width
        72,  # screen pixel height
        MicroCisc::Vm::ColorLcdDisplay::COLOR_MODE_12BIT
      )
    end
    devices = Array.new(17).map { MicroCisc::Vm::EmptyDevice.new }
    devices[15] = terminal # first banked device
    devices[16] = screen
    processor = MicroCisc::Vm::Processor.new(1, 256, rom_blocks)
    processor.devices = devices
    processor.start(ARGV.include?('-d'))
    screen.join if(init_screen)
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

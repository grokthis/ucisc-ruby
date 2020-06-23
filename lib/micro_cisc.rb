require "json"
require "io/wait"
require "tty-screen"

require "micro_cisc/version"
require "micro_cisc/compile/label_generator"
require "micro_cisc/compile/instruction"
require "micro_cisc/compile/statement"

require "micro_cisc/vm/message"
require "micro_cisc/vm/device"
require "micro_cisc/vm/processor"
require "micro_cisc/vm/term_device"
require "micro_cisc/vm/empty_device"
require "micro_cisc/vm/video"
require "micro_cisc/vm/system"

module MicroCisc
  class Error < StandardError; end
  # Your code goes here...
end

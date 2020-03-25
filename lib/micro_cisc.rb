require "json"
require "io/wait"

require "micro_cisc/version"
require "micro_cisc/compile/label_generator"
require "micro_cisc/compile/instruction"
require "micro_cisc/compile/statement"

require "micro_cisc/vm/message"
require "micro_cisc/vm/copy_instruction"
require "micro_cisc/vm/alu_instruction"
require "micro_cisc/vm/page_instruction"
require "micro_cisc/vm/processor"
require "micro_cisc/vm/video"
require "micro_cisc/vm/system"

module MicroCisc
  class Error < StandardError; end
  # Your code goes here...
end

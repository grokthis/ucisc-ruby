require "micro_cisc/version"
require "micro_cisc/compile/label_generator"
require "micro_cisc/compile/instruction"
require "micro_cisc/compile/statement"

require "micro_cisc/vm/copy_instruction"
require "micro_cisc/vm/alu_instruction"
require "micro_cisc/vm/processor"

module MicroCisc
  class Error < StandardError; end
  # Your code goes here...
end

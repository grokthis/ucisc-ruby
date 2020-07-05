$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "micro_cisc"
require "byebug"

MicroCisc.logger.level = "WARN"

require "minitest/autorun"

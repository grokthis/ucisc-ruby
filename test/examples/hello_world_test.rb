require "test_helper"

class HelloWorldExampleTest < Minitest::Test
  SOURCE_FILES = [
    "examples/hello_world.ucisc",
    "core/stdlib.ucisc"
  ]
  def setup
    @compiler = MicroCisc.load(SOURCE_FILES)
    @processor = MicroCisc.run(@compiler.serialize)
  end

  def test_stack_is_unwound
    assert_equal(0x0000, @processor.register(1))
  end

  def test_executed_instructions_is_correct
    assert_equal(128, @processor.count)
  end
end

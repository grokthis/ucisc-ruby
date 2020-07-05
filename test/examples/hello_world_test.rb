require "test_helper"

class HelloWorldExampleTest < Minitest::Test
  def setup
    @compiler = MicroCisc.load("examples/hello_world.ucisc")
    @processor = MicroCisc.run(@compiler.serialize)
  end

  def test_stack_is_unwound
    assert_equal(0x0000, @processor.register(1))
  end

  def test_executed_instructions_is_correct
    assert_equal(103, @processor.count)
  end
end

require "test_helper"

class FibExampleTest < Minitest::Test
  SOURCE_FILES = [
    "examples/fib.ucisc"
  ]
  def setup
    @compiler = MicroCisc.load(SOURCE_FILES)
    @processor = MicroCisc.run(@compiler.serialize)
  end

  def test_stack_is_unwound
    assert_equal(0xFFFF, @processor.register(1))
  end
  def test_fib_six_is_correct
    assert_equal(21, @processor.read_mem(@processor.id, @processor.register(1)))
  end

  def test_executed_instructions_is_correct
    assert_equal(725, @processor.count)
  end
end

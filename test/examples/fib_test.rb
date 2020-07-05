require "test_helper"

class FibExampleTest < Minitest::Test
  def setup
    @compiler = MicroCisc.load("examples/fib.ucisc")
    @processor = MicroCisc.run(@compiler.serialize)
  end

  def test_stack_is_unwound
    assert_equal(0xFFFF, @processor.register(1))
  end
  def test_fib_six_is_correct
    assert_equal(8, @processor.read_mem(@processor.id, @processor.register(1)))
  end

  def test_executed_instructions_is_correct
    assert_equal(271, @processor.count)
  end
end

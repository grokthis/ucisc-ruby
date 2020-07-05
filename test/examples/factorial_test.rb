require "test_helper"

class FactorialExampleTest < Minitest::Test
  def setup
    @compiler = MicroCisc.load("examples/factorial.ucisc")
    @processor = MicroCisc.run(@compiler.serialize)
  end

  def test_stack_is_unwound
    assert_equal(0xFFFF, @processor.register(1))
  end
  def test_four_factorial_is_correct
    assert_equal(24, @processor.read_mem(@processor.id, @processor.register(1)))
  end

  def test_executed_instructions_is_correct
    assert_equal(41, @processor.count)
  end
end

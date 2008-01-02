require 'test/unit'
require 'deltared'

class ConstraintTest < Test::Unit::TestCase
  def test_simple_one_way
    a, b = DeltaRed.variables(0, 0)
    csrt = DeltaRed.constraint! do |c|
      c.formula(a => b) { |v| v * 2 }
    end
    assert_equal 0, a.value
    assert_equal 0, b.value
    b.value = 2
    assert_equal 2, b.value
    assert_equal 4, a.value
    a.value = 3
    assert_equal 4, a.value
    assert_equal 2, b.value
    csrt.disable
    a.value = 3
    assert_equal 3, a.value
    assert_equal 2, b.value
  end
end

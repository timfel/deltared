require 'test/unit'
require 'deltared'

class ConstraintTest < Test::Unit::TestCase
  def test_simple_one_way
    a, b = DeltaRed.variables(1, 1)
    DeltaRed.constraint! do |c|
      c.formula(a => b) { |v| v * 2 }
    end
    assert_equal a.value, b.value * 2
    b.value = 2
    assert_equal 2, b.value
    assert_equal 4, a.value
    a.value = 3
    assert_equal 4, a.value
    assert_equal 2, b.value
  end

  def test_simple_two_way
    a, b = DeltaRed.variables(0, 0)
    DeltaRed.constraint! do |c|
      c.formula(a => b) { |v| v + 1 }
      c.formula(b => a) { |v| v - 1 }
    end
    assert_equal a.value, b.value + 1
    b.value = 2
    assert_equal 2, b.value
    assert_equal 3, a.value
    a.value = 6
    assert_equal 6, a.value
    assert_equal 5, b.value
  end 
end

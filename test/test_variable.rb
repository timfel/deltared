require 'test/unit'
require 'deltared'

class VariableTest < Test::Unit::TestCase
  def test_new
    v = DeltaRed::Variable.new
    assert DeltaRed::Variable === v
  end

  def test_get_value
    v = DeltaRed::Variable.new
    assert_equal nil, v.value
    v = DeltaRed::Variable.new(3)
    assert_equal 3, v.value
  end

  def test_trivial_set_value
    v = DeltaRed::Variable.new(3)
    assert_equal 3, v.value
    v.value = 4
    assert_equal 4, v.value
  end

  def test_variables
    vars = DeltaRed::variables('a', 'b', 'c')
    assert_equal 3, vars.size
    assert vars.all? { |v| DeltaRed::Variable === v }
    vars.uniq!
    assert_equal ['a', 'b', 'c'], vars.map { |v| v.value }
  end

  def test_variables_block
    vars = nil
    result = DeltaRed::variables('a', 'b', 'c') do |a, b, c, d|
      vars = [ a, b, c, d ]
      "foo"
    end
    assert_equal "foo", result
    assert_equal 4, vars.size
    assert vars.all? { |v| DeltaRed::Variable === v }
    vars.uniq!
    assert_equal ['a', 'b', 'c', nil], vars.map { |v| v.value }
  end

  def test_trivial_recompute
    var = DeltaRed::Variable.new(3)
    assert_equal var, var.recompute
    assert_equal 3, var.value
  end
end

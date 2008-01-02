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

  def test_variables
    vars = DeltaRed::variables(3)
    assert_equal 3, vars.size
    vars.uniq!
    assert_equal 3, vars.size
    assert vars.all? { |v| DeltaRed::Variable === v }
  end

  def test_variables_no_count
    assert_raise(ArgumentError) do
      DeltaRed::variables
    end
  end

  def test_variables_block
    vars = DeltaRed::variables do |a, b, c|
      [ a, b, c ]
    end
    assert_equal 3, vars.size
    vars.uniq!
    assert_equal 3, vars.size
    assert vars.all? { |v| DeltaRed::Variable === v }
  end

  def test_trivial_recompute
    var = DeltaRed::Variable.new(3)
    assert_equal var, var.recompute
    assert_equal 3, var.value
  end
end

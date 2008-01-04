require 'test/unit'
require 'deltared'

class ConstraintTest < Test::Unit::TestCase
  def test_constant
    a = DeltaRed::Variable.new(0)
    DeltaRed.constraint! do |c|
      c.formula(a) { 10 }
    end
    assert_equal 10, a.value
    a.value = 20
    assert_equal 10, a.value
  end

  def test_simple_one_way
    a, b = DeltaRed.variables(1, 1)
    DeltaRed.constraint! do |c|
      c.formula(a => b) { |v| v * 2 }
    end
    assert_equal 1, b.value
    assert_equal 2, a.value
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

  def test_one_way_chain
    variables = (0..10).map { DeltaRed::Variable.new(0) }
    head = variables.shift
    variables.inject(head) do |prev, curr|
      DeltaRed.constraint! do |c|
        c.formula(curr => prev) { |v| v }
      end
      curr
    end
    variables.unshift head
    variables.first.value = 10
    assert variables.all? { |v| v.value == 10 }
    variables.first.value = 3
    assert variables.all? { |v| v.value == 3 }
    variables[variables.size / 2].value = 49
    assert variables.all? { |v| v.value == 3 }
    variables.last.value = 22
    assert variables.all? { |v| v.value == 3 }
  end

  def test_two_way_chain
    variables = (0..10).map { DeltaRed::Variable.new(0) }
    head = variables.shift
    variables.inject(head) do |prev, curr|
      DeltaRed.constraint! do |c|
        c.formula(curr => prev) { |v| v }
        c.formula(prev => curr) { |v| v }
      end
      curr
    end
    variables.unshift head
    variables.first.value = 10
    assert variables.all? { |v| v.value == 10 }
    variables.first.value = 3
    assert variables.all? { |v| v.value == 3 }
    variables[variables.size / 2].value = 49
    assert variables.all? { |v| v.value == 49 }
    variables.last.value = 22
    assert variables.all? { |v| v.value == 22 }
  end

  def test_many_to_one
    x, y, z = DeltaRed.variables(1, 1, 1)
    DeltaRed.constraint! do |c|
      c.formula(x => [y, z]) { |a, b| a + b }
    end
    assert_equal 1, z.value
    assert_equal 1, y.value
    assert_equal 2, x.value
    y.value = 3
    assert_equal 3, y.value
    assert_equal 1, z.value
    assert_equal 4, x.value
    z.value = 4
    assert_equal 4, z.value
    assert_equal 3, y.value
    assert_equal 7, x.value
    x.value = 0
    assert_equal 7, x.value
    assert_equal 4, z.value
    assert_equal 3, y.value
  end

  def test_many_to_one_two_way
    x, y, z = DeltaRed.variables(1, 1, 1)
    DeltaRed.constraint! do |c|
      c.formula(x => [y, z]) { |a, b| a + b }
      c.formula(y => [x, z]) { |a, b| a - b }
      c.formula(z => [x, y]) { |a, b| a - b }
    end
    assert_equal x.value, y.value + z.value
    y.value = 3
    assert_equal 3, y.value
    assert_equal x.value, y.value + z.value
    z.value = 4
    assert_equal 4, z.value
    assert_equal 3, y.value
    assert_equal 7, x.value
    x.value = 0
    assert_equal 0, x.value
    assert_equal x.value, y.value + z.value
  end

  def test_volatile_formula_makes_volatile
    x = DeltaRed::Variable.new
    constraint = DeltaRed.constraint do |c|
      c.volatile_formula(x) { }
    end
    assert constraint.volatile?
  end
end

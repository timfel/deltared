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

  def test_stay_and_edit_constraints
    a = DeltaRed::Variable.new(0)
    a.stay!(DeltaRed::MEDIUM)

    c = a.edit!(1, DeltaRed::WEAKEST)
    assert_equal 0, a.value
    c.disable
    assert_equal 0, a.value

    c = a.edit!(2, DeltaRed::REQUIRED)
    assert_equal 2, a.value
    c.disable
    assert_equal 2, a.value
  end

  def test_simple_volatile
    a = DeltaRed::Variable.new(0)
    val = 20
    DeltaRed.constraint! do |c|
      c.volatile_formula(a) { val }
    end
    assert_equal 0, a.value
    val = 30
    assert_equal 0, a.value
    a.recompute
    assert_equal 30, a.value
  end

  def test_simple_no_block
    a, b = DeltaRed.variables(1, 1)
    DeltaRed.constraint! do |c|
      c.formula(b => a)
    end
    b.value = 2
    assert_equal 2, a.value
  end

  def test_multiple_inputs_no_block
    x, y, z = DeltaRed.variables(nil, 2, 3)
    DeltaRed.constraint! do |c|
      c.formula([y, z] => x)
    end
    assert_equal [2, 3], x.value
  end

  def test_simple_one_way
    a, b = DeltaRed.variables(1, 1)
    DeltaRed.constraint! do |c|
      c.formula(b => a) { |v| v * 2 }
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
      c.formula(b => a) { |v| v + 1 }
      c.formula(a => b) { |v| v - 1 }
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
    assert variables.all? { |v| v.value == 3 }
    variables.last.value = 22
    assert variables.all? { |v| v.value == 3 }
  end

  def test_two_way_chain
    variables = (0..10).map { DeltaRed::Variable.new(0) }
    head = variables.shift
    variables.inject(head) do |prev, curr|
      DeltaRed.constraint! do |c|
        c.formula(prev => curr) { |v| v }
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
    assert variables.all? { |v| v.value == 49 }
    variables.last.value = 22
    assert variables.all? { |v| v.value == 22 }
  end

  def test_many_to_one
    x, y, z = DeltaRed.variables(1, 1, 1)
    DeltaRed.constraint! do |c|
      c.formula([y, z] => x) { |a, b| a + b }
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
      c.formula([y, z] => x) { |a, b| a + b }
      c.formula([x, z] => y) { |a, b| a - b }
      c.formula([x, y] => z) { |a, b| a - b }
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

  def test_volatile_formula_exception
    x = DeltaRed::Variable.new(42)
    constraint = DeltaRed.constraint! do |c|
      c.volatile_formula(x) { raise "blah" }
    end
    assert_equal 42, x.value
    x.recompute
    assert_raise(DeltaRed::FormulaError) do
      x.value
    end
  end

  def test_one_way_constraint
    a, b = DeltaRed.variables(1, 1)
    assert_equal 1, a.value
    assert_equal 1, b.value
    b.constraint!(a) { |v| v * 2 }
    assert_equal 1, a.value
    assert_equal 2, b.value
    a.value = 3
    assert_equal 3, a.value
    assert_equal 6, b.value
  end

  def test_output
    x, y = DeltaRed.variables(0, 0)
    values = nil
    constraint = DeltaRed.output(x, y) { |x_, y_| values = [x_, y_] }
    assert DeltaRed::Constraint === constraint
    assert_equal [0, 0], values
    x.value = 1
    assert_equal [1, 0], values
    y.value = 2
    assert_equal [1, 2], values
  end

  def test_output_no_variables
    assert_raise ArgumentError do
      constraint = DeltaRed.output {}
    end
  end

  def test_output_no_block
    x, y = DeltaRed.variables(0, 0)
    assert_raise ArgumentError do
      constraint = DeltaRed.output(x, y)
    end
  end
end

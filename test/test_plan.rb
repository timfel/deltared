require 'test/unit'
require 'deltared'

class PlanTest < Test::Unit::TestCase
  def test_plan_recompute
    a_val = 1
    b_val = 11
    a, b = DeltaRed.variables(0, 0)
    DeltaRed.constraint! do |c|
      c.volatile_formula(a) { a_val }
    end
    b_constraint = DeltaRed.constraint! do |c|
      c.volatile_formula(b) { b_val }
    end
    assert_equal 1, a.value
    assert_equal 11, b.value
    a_val = 2
    b_val = 12
    plan = DeltaRed.plan_recompute(a, b_constraint)
    assert_equal 1, a.value
    assert_equal 11, b.value
    plan.recompute
    assert_equal 2, a.value
    assert_equal 12, b.value
  end
end

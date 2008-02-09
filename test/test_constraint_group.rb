require 'test/unit'
require 'deltared'

class ConstraintGroupTest < Test::Unit::TestCase
  def test_group
    vars = DeltaRed.variables(*(0..4))
    constraints = vars.map { |v| v.constraint {} }
    group = DeltaRed.group(*constraints)
    assert constraints.all? { |c| !c.enabled? }
    group.enable
    assert constraints.all? { |c| c.enabled? }
    group.disable
    assert constraints.all? { |c| !c.enabled? }
  end
end

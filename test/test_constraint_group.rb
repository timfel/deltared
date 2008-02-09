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

  def test_group_capture
    vars = DeltaRed.variables(*(0..4))
    constraints = nil
    group = nil
    group2 = DeltaRed.group do
      group = DeltaRed.group do
        constraints = vars.map { |v| v.constraint {} }
      end
    end
    assert constraints.all? { |c| !c.enabled? }
    group.enable
    assert constraints.all? { |c| c.enabled? }
    group.disable
    assert constraints.all? { |c| !c.enabled? }
    group2.enable
    assert constraints.all? { |c| c.enabled? }
    group2.disable
    assert constraints.all? { |c| !c.enabled? }
  end
end

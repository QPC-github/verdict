require 'test_helper'

class GroupTest < MiniTest::Unit::TestCase

  def setup
    @experiment = Experiments::Experiment.new('a')
  end

  def teardown
    Experiments.repository.clear
  end

  def test_basic_properties
    group = Experiments::Group.new(@experiment, :test)

    assert_equal @experiment, group.experiment
    assert_kind_of Experiments::Group, group
    assert_equal 'test', group.label
    assert_equal 'test', group.to_s
    assert_equal :test, group.to_sym
  end

  def test_triple_equals
    group = Experiments::Group.new(@experiment, 'control')
    assert group === Experiments::Group.new(@experiment, :control)
    assert group === 'control'
    assert group === :control
    assert !(group === nil)

    assert !(group === Experiments::Group.new(@experiment, :test))
    assert !(group === Experiments::Group.new(Experiments::Experiment.new('b'), :test))
    assert !(group === 'test')
    assert !(group === nil)
  end
end

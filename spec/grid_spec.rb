require 'spec_helper'

class ExpandingGrid

  attr_reader :top, :left, :bottom, :right, :fringe, :default, :options

  def initialize(options = {})
    @options = options.frozen? ? options : options.dup.freeze
    @fringe = options[:fringe] || 0
    @top, @left, @bottom, @right = 0, 0, 0, 0
    @grid = {}
    @default = options[:default]
    fit(0, 0)
  end

  def at(x, y)
    position, value = @grid.assoc([x, y])
    position ? value : @default
  end

  def each(selection = :all, &block)
    @top.downto(@bottom).each do |y|
      @left.upto(@right).each do |x|
        value = at(x, y)
        unless value == @default and selection == :set
          yield value, x, y
        end
      end
    end
  end

  def each_around(x, y, &block)
    (y + 1).downto(y - 1).each do |at_y|
      (x - 1).upto(x + 1).each do |at_x|
        value = at(at_x, at_y)
        unless value == @default or (at_x == x && at_y == y)
          yield value, at_x, at_y
        end
      end
    end
  end

  def height
    @top - @bottom + 1
  end

  def width
    @right - @left + 1
  end

  def replace(other)
    other.instance_variables.each do |variable|
      instance_variable_set variable, other.instance_variable_get(variable)
    end
  end

  def set(x, y, object)
    if object == @default
      unset(x, y)
    else
      @grid[[x, y]] = object
      fit(x, y)
    end
    self
  end

  def shrink
    shrunk = self.class.new(@options)
    each(:set) do |o, x, y|
      shrunk.set(x, y, o)
    end
    replace(shrunk)
  end

  def unset(x, y)
    @grid.delete([x, y])
    self
  end

  private

  def fit(x, y)
    @left   = x - @fringe if x <= @left   + @fringe
    @right  = x + @fringe if x >= @right  - @fringe
    @bottom = y - @fringe if y <= @bottom + @fringe
    @top    = y + @fringe if y >= @top    - @fringe
  end

end

RSpec::Matchers.define :have_geometry do |dimensions|
  match do |grid|
    dimensions.each do |dimension, value|
      grid.send(dimension).should == value
    end
  end
end

describe ExpandingGrid do

  describe "#new(options = {})" do

    it "takes and stores options" do
      grid = ExpandingGrid.new(fringe: 0, default: nil)
      grid.options.should == { fringe: 0, default: nil }
    end

    it "takes option :fringe" do
      grid = ExpandingGrid.new(fringe: 42)
      grid.fringe.should == 42
    end

    it "takes the default value as option :default" do
      grid = ExpandingGrid.new(default: :custom_default_value)
      grid.default.should == :custom_default_value
    end

  end

  describe "expansion" do

    let(:grid) { ExpandingGrid.new }
    let(:default_geometry) { { width: 1, height: 1, left: 0, right: 0, top: 0, bottom: 0 } }

    it "starts off 1x1 at 0,0" do
      grid.should have_geometry(default_geometry)
    end

    it "grows to the right" do
      grid.set 2, 0, :dot
      grid.should have_geometry(default_geometry.merge width: 3, right: 2)
    end

    it "grows to the left" do
      grid.set -2, 0, :dot
      grid.should have_geometry(default_geometry.merge width: 3, left: -2)
    end

    it "grows up" do
      grid.set 0, 2, :dot
      grid.should have_geometry(default_geometry.merge height: 3, top: 2)
    end

    it "grows down" do
      grid.set 0, -2, :dot
      grid.should have_geometry(default_geometry.merge height: 3, bottom: -2)
    end

    describe "with fringe" do

      let(:grid) { ExpandingGrid.new(fringe: 5) }
      let(:default_geometry) { { width: 11, height: 11, left: -5, right: 5, top: 5, bottom: -5 } }

      it "starts off fringed" do
        grid.should have_geometry(default_geometry)
      end

      it "grows fringed as well" do
        grid.set( 3, 3, :dot ).set( -4, -4, :dot )
        grid.should have_geometry( width: 18, height: 18, left: -9, right: 8, top: 8, bottom: -9 )
      end

    end

  end

  describe "shrinking" do
    let(:grid) { ExpandingGrid.new.set(0, 0, :mid).set(-1, 1, :top_left).set(1, -1, :bottom_right) }

    it "shrinks to fit currently set positions and fringe" do
      grid.unset(-1, 1).unset(1, -1)
      grid.shrink
      grid.width.should == 1 + grid.fringe
      grid.width.should == 1 + grid.fringe
    end

  end 

  describe "#at" do

    let(:grid) { ExpandingGrid.new(fringe: 1) }

    it "locates value set at coordinates" do
      grid.set(0, 0, :dot).at(0, 0).should == :dot
    end

    it "doesn't expand when locating out of range coordinates" do
      grid.at(2, 2)
      grid.width.should == 3
      grid.height.should == 3
    end

    context "when the default value is unset (nil)" do

      let(:grid) { ExpandingGrid.new(fringe: 1) }

      it "returns nil for unset values" do
        grid.at(1, 1).should be_nil
      end

      it "returns nil for out of range coordinates" do
        grid.at(2, 2).should be_nil
      end

    end

    context "when the default value is set" do

      let(:grid) { ExpandingGrid.new(fringe: 1, default: :specific_default_value) }

      it "returns the default value for unset values" do
        grid.at(1, 1).should == grid.default
      end

      it "returns the default value for out of range coordinates" do
        grid.at(2, 2).should == grid.default
      end

      it "returns nil for values set to nil" do
        grid.set(1, 1, nil).at(1, 1).should be_nil
      end

    end

  end

  describe "#each" do

    let(:grid) { ExpandingGrid.new.set(0, 0, :mid).set(-1, 1, :top_left).set(1, -1, :bottom_right) }
    let(:values) { a = []; grid.each { |o| a << o }; a }
    let(:coordinates) { a = []; grid.each { |o, x, y| a << [x, y] }; a }

    it "yields the value at each position from top left to bottom right, row by row" do
      expected = [ :top_left, nil,     nil,
                   nil,       :mid,    nil,
                   nil,       nil,     :bottom_right ]
      values.should == expected
    end

    it "yields the coordinates in addition to the value at each position" do
      expected = [ [-1, 1],  [0, 1],  [1, 1],
                   [-1, 0],  [0, 0],  [1, 0],
                   [-1, -1], [0, -1], [1, -1] ]
      coordinates.should == expected
    end

  end

  describe "#each(:set)" do
    let(:grid) { ExpandingGrid.new(default: :nil).set(0, 0, :mid).set(-1, 1, :top_left).set(1, -1, :bottom_right) }
    let(:values) { a = []; grid.each(:set) { |o| a << o }; a }
    let(:coordinates) { a = []; grid.each(:set) { |o, x, y| a << [x, y] }; a }

    it "yields the value at each position that is set, from top left to bottom right, row by row" do
      expected = [ :top_left, :mid, :bottom_right ]
      values.should == expected
    end

    it "yields the coordinates in addition to the value at each position that is set" do
      expected = [ [-1, 1], [0, 0], [1, -1] ]
      coordinates.should == expected
    end

  end

  describe "#set" do
    let(:grid) { ExpandingGrid.new(fringe: 0, default: :specific_default_value) }

    it "completely removes the coordinates from internal storage if the value to set is the default value" do
      grid.set(0, 0, :dot).set(0, 0, :specific_default_value)
      grid.instance_variable_get(:@grid).should_not include([0, 0])
    end

  end

  describe "#each_around(x, y)" do

    let(:grid) { ExpandingGrid.new.set(0, 0, :mid).set(-1, 1, :top_left).set(1, -1, :bottom_right) }
    let(:values) { a = []; grid.each_around(0, 0) { |o| a << o }; a }
    let(:coordinates) { a = []; grid.each_around(0, 0) { |o, x, y| a << [x, y] }; a }

    it "yields the value at each position around x and y, from top left to bottom right, row by row" do
      values.should == [ :top_left, :bottom_right ]
    end

    it "yields the coordinates in addition to the value at each position around x and y" do
      coordinates.should == [ [-1, 1], [1, -1] ]
    end

  end

end

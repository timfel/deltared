# DeltaRed - A multi-way constraint solver for Ruby
#
# Copyright 2007-2008  MenTaLguY <mental@rydia.net>
#
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * The names of the authors may not be used to endorse or promote products
#   derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

require 'set'

class Set #:nodoc:
  instance_methods = self.instance_methods
  unless instance_methods.include? "shift" or instance_methods.include? :shift
    def shift
      value = find { true }
      delete value
      value
    end
  end
end

# This implementation is very closely based on the pseudocode presented in
# the appendix of "Multi-way versus One-way Constraints in User Interfaces:
# Experience with the DeltaBlue Algorithm" by Sannella et al., available at
# http://citeseer.ist.psu.edu/sannella93multiway.html
#
module DeltaRed

class Mark #:nodoc:
end 

REQUIRED = 4 # the highest constraint strength; fails if it cannot be enforced
STRONG   = 3 
MEDIUM   = 2
WEAK     = 1
WEAKEST  = 0 # the weakest constraint strength

# Variables are holders for values.  Relationships between
# the values of different variables can be enforced by 
# creating Constraint objects referencing those variables.
#
# Variables can be created via Variable.new or DeltaRed.variables.
#
class Variable
  attr_reader   :value         # the variable's current value
  attr_writer   :value         #:nodoc:
  attr_reader   :constraints   #:nodoc:
  attr_accessor :determined_by #:nodoc:
  attr_accessor :walk_strength #:nodoc:
  attr_accessor :stay          #:nodoc:
  attr_writer   :mark	       #:nodoc:
  send :alias_method, :__value__=, :value=
  send :alias_method, :mark, :mark=
  undef mark=
  send :alias_method, :stay?, :stay

  # Creates a new constraint variable with an initial +value+ (or
  # +nil+ if none is provided).
  def initialize(value=nil)
    @value = value
    @constraints = Set.new
    @determined_by = nil
    @walk_strength = WEAKEST
    @mark = nil
    @stay = true
    @edit_constraint = nil
  end

  def remove_propagate_from #:nodoc:
    unenforced = Set.new
    @determined_by = nil
    @walk_strength = WEAKEST
    @stay = true
    todo = Set[self]
    until todo.empty?
      variable = todo.shift
      for constraint in variable.constraints
        unenforced.add constraint unless constraint.enforcing_method
      end
      for constraint in variable.consuming_constraints
        constraint.recompute_incremental
        todo.add constraint.enforcing_method.output
      end
    end
    # sort by decreasing strength
    unenforced.to_a.sort! { |a, b| b.strength <=> a.strength }
  end

  # Recomputes the variable's value if its value is determined by
  # external input.
  def recompute
    Plan.new_from_variables(self).execute
    self
  end

  def consuming_constraints #:nodoc:
    @constraints.select { |c|
      c.enforcing_method and c != @determined_by
    }.to_set
  end

  def marked?(mark) #:nodoc:
    @mark.eql? mark
  end

  # Sets the variable to a specific +value+ and propagates
  # it with a strength of +REQUIRED+; conceptually (and actually,
  # for the moment), this creates a constant-value constraint and
  # briefly enables it to force the variable's value to the desired
  # value.
  def value=(value)
    unless @edit_constraint
      @edit_method = EditMethod.new(self, value)
      @edit_constraint = Constraint.__new__([self], REQUIRED,
                                            false, [@edit_method])
    else
      @edit_method.value = value
    end
    @edit_constraint.enable.disable
    value
  end
end

# A Constraint determines the values of some variables (its "outputs")
# based on the values of other variables (its "inputs") and possibly
# also external input.  In the case of conflicts, constraints with
# higher strengths take precdence over constraints with lower
# strengths.
#
# New constraints are initially disabled, and must be enabled with
# Constraint#enable before they will have an effect.
#
# See also Variable.
#
class Constraint
  attr_reader :enabled   # whether this constraint is currently enabled
  attr_reader :variables # the input and output variables for this constraint
  # the strength of this constraint, generally a value between
  # WEAKEST and REQUIRED
  attr_reader :strength
  # boolean indicating whether the constraint's outputs are determined
  # by anything besides its input variables (for example, user input)
  attr_reader :external_input
  attr_reader :enforcing_method #:nodoc:
  alias external_input? external_input
  alias enabled? enabled

  class << self
    send :alias_method, :__new__, :new
    # Uses a Constraint::Builder to build a new Constraint; call
    # Constraint::Builder#compute on the yielded +builder+ to
    # specify how each output variable is computed.
    #
    # +strength+ is the strength of the new constraint, and
    # +external_input+ is a boolean indicating whether any of the
    # constraint's outputs can be affected by anything besides
    # the values of its inputs.
    #
    # See also DeltaRed.constraint.
    #
    def build(strength=MEDIUM, external_input=false)
      raise ArgumentError, "No block given" unless block_given?
      builder = Builder.new(strength, external_input)
      yield builder
      builder.build
    end
    alias new build
  end

  def initialize(variables, strength, external_input, methods) #:nodoc:
    @variables = variables.freeze
    @strength = strength
    @external_input = external_input
    @methods = methods.freeze
    @enforcing_method = nil
    @enabled = false
  end

  # Creates a copy of this constraint with its variables replaced with
  # other variables as specified by +map+.  This is useful if you want
  # to use a constraint as a "template" for creating other constraints
  # over different variables.
  #
  # Returns the new constraint.
  #
  def substitute(map)
    variables = @variables.map { |v| map[v] || v }.uniq
    methods = @methods.map { |m| m.substitute(map) }
    Constraint.__new__(variables, @strength, @external_input, methods)
  end

  # Enables this constraint, adjusting the values of any variables as needed.
  def enable
    return @self if @enabled
    @enforcing_method = nil
    for variable in @variables
      variable.constraints.add self
    end
    incremental_add
    @enabled = true
    self
  end

  def incremental_add #:nodoc:
    mark = Mark.new
    retracted = enforce(mark)
    while retracted
      retracted = retracted.enforce(mark)
    end
    self
  end

  def enforce(mark) #:nodoc:
    @enforcing_method = weakest_method(mark)
    if @enforcing_method
      inputs.each { |v| v.mark mark }
      output = @enforcing_method.output
      retracted = output.determined_by
      retracted.unenforce if retracted
      output.determined_by = self
      add_propagate(mark)
      @enforcing_method.output.mark mark
      retracted
    else
      if @strength >= REQUIRED
        raise RuntimeError, "Failed to enforce a required constraint"
      end
      nil
    end
  end
  private :enforce #:nodoc:

  def unenforce #:nodoc:
    @enforcing_method = nil
    self
  end

  def weakest_method(mark) #:nodoc:
    weakest_method = nil
    weakest_strength = @strength
    for method in @methods
      output = method.output
      if not output.marked? mark and output.walk_strength < weakest_strength
        weakest_strength = output.walk_strength
        weakest_method = method
      end
    end
    weakest_method
  end
  private :weakest_method #:nodoc:

  def add_propagate(mark) #:nodoc:
    todo = Set[self]
    until todo.empty?
      constraint = todo.shift
      if constraint.enforcing_method.output.marked? mark
        constraint.incremental_remove
        raise RuntimeError, "Cycle encountered"
      end
      constraint.recompute_incremental
      todo.merge constraint.enforcing_method.output.consuming_constraints
    end
    self
  end

  # Disables this constraint, adjusting the values of any variables as needed.
  def disable
    return self unless @enabled
    if @enforcing_method
      incremental_remove
    else
      for variable in @variables
        variable.constraints.delete self
      end
    end
    @enabled = false
    self
  end

  def incremental_remove #:nodoc:
    out = @enforcing_method.output
    @enforcing_method = nil
    for variable in @variables
      variable.constraints.delete self
    end
    for constraint in out.remove_propagate_from
      constraint.incremental_add
    end
    self
  end

  def inputs #:nodoc:
    output = @enforcing_method.output
    @variables.select { |v| v != output }
  end
  private :inputs #:nodoc:

  def inputs_known?(mark) #:nodoc:
    inputs.all? { |v| v.marked? mark or v.stay? }
  end

  def recompute_incremental #:nodoc:
    output = @enforcing_method.output
    output.walk_strength = output_walk_strength
    stay = output.stay = constant_output?
    @enforcing_method.execute if stay
    self
  end

  # Recomputes the constraint's outputs if the constraint
  # uses external input.
  def recompute
    Plan.new_from_constraints(self).execute
    self
  end

  def constant_output? #:nodoc:
    not external_input? and inputs.all? { |v| v.stay? }
  end

  def output_walk_strength #:nodoc:
    min_strength = strength
    output = @enforcing_method.output
    for method in @methods
      if method.output != output and method.output.walk_strength < min_strength
        min_strength = method.output.walk_strength
      end
    end
    min_strength
  end
  private :output_walk_strength #:nodoc:
end

class Constraint::Builder
  def initialize(strength=MEDIUM, external_input=false)
    @methods = []
    @variables = Set.new
    @strength = strength
    @external_input = !!external_input
  end

  # Specifies an output variable for this constraint, optionally depending
  # on the value of other variables.  The block will be called whenever
  # the variable's value needs to be recomputed; it receives the values
  # of any input variables as arguments, and its result becomes the new
  # value of the variable.
  #
  # Examples (+a+, +b+ and +c+ are all Variable objects):
  # 
  # +a+ is 3 times the value of +b"
  #
  #  builder.compute(a => b) { |b_value| b_value * 3 }
  # 
  # +a+ is the sum of the values of +b+ and +c+
  #
  #  builder.compute(a => [ b, c ]) do |b_value, c_value|
  #   b_value + c_value
  #  end
  #
  # +a+ is fixed at 30 (unless a stronger constraint overrides)
  #
  #  builder.compute(a) { 30 }
  #
  # +a+ is determined by the current mouse position -- note that
  # external_input should be set for this constraint!
  #
  #  builder.compute(a) { window.mouse_x }
  #
  def compute(args, &code) #:yields:*values
    raise ArgumentError, "Block expected" unless code
    case args
    when Hash
      raise ArgumentError, "Multiple output variables not allowed" if args.size > 1
      raise ArgumentError, "No output variable given" if args.empty?
      output = args.keys[0]
      inputs = Array(args[output])
    else
      output = args
      inputs = []
    end
    @variables.add output
    @variables.merge inputs
    @methods.push UserMethod.new(output, inputs, code)
    self
  end

  # Builds a new Constraint based on the outputs that have been
  # specified so far.
  def bulid
    raise RuntimeError, "No outputs defined" if @methods.empty?
    Constraint.__new__(@variables.to_a, strength, @external_input, @methods.dup)
  end
end

module Method #:nodoc:
  def output
    raise NotImplementedError, "#{self.class}#output not implemented"
  end

  def execute
    raise NotImplementedError, "#{self.class}#execute not implemented"
  end

  def substitute(map)
    raise NotImplementedError, "#{self.class}#substitute not implemented"
  end
end

class EditMethod #:nodoc:
  include Method
  attr_reader :output
  attr_accessor :value

  def initialize(output, value)
    @output = output
    @value = value
  end

  def execute
    @output.__value__ = @value
    self
  end

  def substitute(map)
    EditMethod.new(map[@output] || @output, value)
  end
end

class UserMethod #:nodoc:
  include Method
  attr_reader :output

  def initialize(output, inputs, code)
    @output = output
    @inputs = inputs
    @code = code
  end

  def execute
    @output.__value__ = @code.call *@inputs.map { |i| i.value }
    self
  end

  def substitute(map)
    output = map[@output] || @output
    inputs = @inputs.map { |i| map[i] || i }
    UserMethod.new(output, inputs, @code)
  end
end

# A Plan provides an optimized way to recompute variables without enabling
# or disabling constraints.  A Plan remains valid only until a constraint
# is changed.
#
class Plan
  class << self
    private :new

    def null #:nodoc:
      new([])
    end

    # Creates and returns an update Plan for updating the given variables
    # and any variables which depend on them.
    def new_from_variables(*variables)
      sources = Set.new
      for variable in variables
        for constraint in variable.constraints
          if constraint.external_input? and constraint.enforcing_method
            sources.add constraint
          end
        end
      end
      unless sources.empty?
        new(sources)
      else
        NULL_PLAN
      end
    end

    # Creates and returns an update Plan for updating variables influenced
    # by the given constraints.
    def new_from_constraints(*constraints)
      sources = Set.new
      for constraint in constraints
        if constraint.external_input? and constraint.enforcing_method
          sources.add constraint
        end
      end
      unless sources.empty?
        new(sources)
      else
        NULL_PLAN
      end
    end
  end

  def initialize(sources) #:nodoc:
    @plan = []
    mark = Mark.new
    hot = sources
    until hot.empty?
      constraint = hot.shift
      enforcing_method = constraint.enforcing_method
      output = enforcing_method.output
      if not output.marked? mark and constraint.inputs_known? mark
        @plan.push enforcing_method
        output.mark mark
        hot.merge output.consuming_constraints
      end
    end
  end

  # Executes the update plan, recomputing the output values of the
  # any variables affected by the plan.
  def execute
    @plan.each { |method| method.execute }
    self
  end

  NULL_PLAN = Plan.null #:nodoc:
end

# Uses a Constraint::Builder to build a new Constraint; call
# Constraint::Builder#compute on the yielded +builder+ to
# specify how each output variable is computed.
#
# This method is a wrapper around Constraint.build.
#
def self.constraint(strength=STRONG, external_input=false)
  raise ArgumentError, "No block given" unless block_given?
  Constraint.new(strength, external_input) { |builder| yield builder }
end

# Creates +count+ new variables.  If a block is provided, the
# new variables are passed to the block as arguments, and an
# explicit count is not normally then required; a new variable
# will be provided for every block argument.
#
# See Variable.
#
# Examples:
#
#  a, b, c = DeltaRed.variables(3)
#  # a, b, and c are new Variable objects
#
#  DeltaRed.variables do |a, b, c|
#    # a, b, and c are new Variable objects
#  end
#
def self.variables(count=nil, &block)
  if block
    if count
      raise ArgumentError, "Too many variables" if count > block.arity
    else
      count = block.arity
      raise ArgumentError, "Number of variables not specified" if count < 0
    end
  else
    raise ArgumentError, "Number of variables not specified" unless count
    raise ArgumentERror, "Count is negative" if count < 0
  end
  variables = (0...count).map { Variable.new }
  if block
    block.call *variables
  else
    variables
  end
end

end

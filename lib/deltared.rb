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

module DeltaRed

class FormulaError < RuntimeError
  attr_reader :reason
  def initialize(reason)
    super("#{reason.class}: #{reason.message}")
    @reason = reason
  end
end

class Mark #:nodoc:
end 

REQUIRED = 4 # the highest constraint strength; fails if it cannot be enforced
STRONG   = 3 
MEDIUM   = 2
WEAK     = 1
WEAKEST  = 0 # the weakest constraint strength

# Variables have values which may be determined by constraints.
# See Constraint.
#
class Variable
  attr_reader   :constraints   #:nodoc:
  attr_accessor :determined_by #:nodoc:
  attr_accessor :walk_strength #:nodoc:
  attr_accessor :constant          #:nodoc:
  attr_writer   :mark	       #:nodoc:

  # hide from rdoc
  send :alias_method, :mark, :mark=
  send :alias_method, :constant?, :constant
  undef mark=

  # Creates a new constraint variable with an initial +value+ (or
  # +nil+ if none is provided).  See also DeltaRed.variables.
  def initialize(value=nil)
    @value = value
    @constraints = Set.new
    @determined_by = nil
    @walk_strength = WEAKEST
    @mark = nil
    @constant = true
    @edit_constraint = nil
    @deferred = nil
  end

  # the variable's current value
  def value
    return @value unless @deferred
    @value = @deferred.call
    @deferred = nil
    @value
  end

  def __value__=(value) #:nodoc:
    @deferred = nil
    @value = value
  end

  def __deferred__=(deferred) #:nodoc:
    @value = nil
    @deferred = deferred
  end

  def remove_propagate_from #:nodoc:
    unenforced = Set.new
    @determined_by = nil
    @walk_strength = WEAKEST
    @constant = true
    todo = Set[self]
    until todo.empty?
      variable = todo.shift
      for constraint in variable.constraints
        unenforced.add constraint unless constraint.enforcing_method
      end
      for constraint in variable.consuming_constraints
        constraint.compute_incremental
        todo.add constraint.enforcing_method.output
      end
    end
    # sort by decreasing strength
    unenforced.to_a.sort! { |a, b| b.strength <=> a.strength }
  end

  # Recomputes the variable's value and returns +self+.  Really only
  # useful if this variable is directly determined by a volatile constraint.
  def recompute
    Plan.new(self).recompute unless @constraints.empty?
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

  # Sets the variable to a specific +value+.  Conceptually, this briefly
  # enables a constant-value constraint on the variable with a strength of
  # +STRONG+ in order to force the variable to the desired value.  Of
  # course, since the "edit constraint" doesn't remain, other constraints
  # may prevent the new value from taking.
  #
  def value=(value)
    if @constraints.empty?
      @value = value
    else
      unless @edit_constraint
        @edit_method = EditMethod.new(self, value)
        @edit_constraint = Constraint.__new__([self], STRONG,
                                              false, [@edit_method])
      else
        @edit_method.value = value
      end
      @edit_constraint.enable.disable
    end
    value
  end

  def inspect #:nodoc:
    "#<DeltaRed::Variable object_id=#{object_id} value=#{@value.inspect}>"
  end
  send :alias_method, :to_s, :inspect
end

# A Constraint determines the values of some variables (its "outputs")
# based on the values of other variables (its "inputs") and possibly
# also external input.  In the case of conflicts, constraints with
# higher strengths take precdence over constraints with lower
# strengths.
#
# Constraints can be either <em>volatile</em> or <em>non-volatile</em>,
# depending on whether they take input from sources outside the constraint
# system.  Non-volatile constraints have less overhead since they do not
# need to be recomputed all the time.
#
# A constraint may be created using a Constraint::Builder, typically
# by calling DeltaRed.constraint.  Newly created constraints are
# disabled by default, and must be enabled by calling Constraint#enable
# before they will have an effect.  Alternately you can use
# DeltaRed.constraint! to construct and enable a constraint in one
# go.
#
# See also Variable.
#
class Constraint
  # boolean indicating whether this constraint is currently enabled
  attr_reader :enabled
  attr_reader :variables #:nodoc:
  # the strength of this constraint, generally a value between
  # DeltaRed::WEAKEST and DeltaRed::REQUIRED, inclusive (for instance:
  # WEAKEST, WEAK, MEDIUM, STRONG or REQUIRED)
  attr_reader :strength
  # boolean indicating whether the constraint has volatile formulae
  attr_reader :volatile
  attr_reader :enforcing_method #:nodoc:
  alias volatile? volatile
  alias enabled? enabled

  # duck-typing for plan seeding
  def constraints #:nodoc:
    [self]
  end

  class << self
    send :alias_method, :__new__, :new
    def new(strength=MEDIUM)
      raise ArgumentError, "No block given" unless block_given?
      builder = Builder.new(strength)
      yield builder
      builder.build
    end
  end

  def initialize(variables, strength, volatile, methods) #:nodoc:
    @variables = variables.freeze
    @strength = strength
    @volatile = volatile
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
    Constraint.__new__(variables, @strength, @volatile, methods)
  end

  # Enables this constraint, recomputing the values of any variables as needed,
  # and returns +self+.
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
      constraint.compute_incremental
      todo.merge constraint.enforcing_method.output.consuming_constraints
    end
    self
  end

  # Disables this constraint, recomputing the values of any variables as needed,
  # and returns +self+.
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
    inputs.all? { |v| v.marked? mark or v.constant? }
  end

  def compute_incremental #:nodoc:
    output = @enforcing_method.output
    output.walk_strength = output_walk_strength
    output.constant = !@volatile && inputs.all? { |v| v.constant? }
    # precompute volatile constraints too; better matches naive expectations
    @enforcing_method.call
    self
  end

  # Recomputes the constraint's output variables and returns +self+.  Really
  # only useful if this constraint is volatile.
  def recompute
    Plan.new(self).recompute
    self
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

  def inspect #:nodoc:
    "#<DeltaRed::Constraint object_id=#{object_id} variables=#{@variables.inspect} enabled=#{@enabled.inspect}>"
  end
  send :alias_method, :to_s, :inspect
end

# Constraint builders are used to construct user-generated constraints
# by calling formula to define output variables and then build to build
# the corresponding constraint.
class Constraint::Builder
  def initialize(strength=MEDIUM)
    @methods = []
    @outputs = Set.new
    @strength = strength
    @volatile = false
  end

  # hide from rdoc
  send :const_set, :NOOP_PROC, proc { |v| v }
  send :const_set, :SPLAT_PROC, proc { |*vs| vs }

  # Defines an output variable for this constraint, optionally depending
  # on the value of other variables.  The block specifies a formula which
  # will be evaluated whenever the variable's value needs to be recomputed;
  # it receives the values of any input variables as arguments, and its
  # result becomes the new value of the variable.
  #
  # Because the block is only called when its input change, the formula
  # should be "pure": its result should not depend on anything but its
  # inputs.  Formulae which depend on other things (e.g. GUI events)
  # may need to be evaluated more often and should be defined using
  # volatile_formula instead.
  #
  # Returns +self+.
  #
  # Examples (+a+, +b+ and +c+ are all Variable objects):
  # 
  # +a+ is 3 times the value of +b+
  #
  #  builder.formula(b => a) { |b_value| b_value * 3 }
  # 
  # +a+ is the sum of the values of +b+ and +c+
  #
  #  builder.formula([ b, c ] => a) do |b_value, c_value|
  #    b_value + c_value
  #  end
  #
  # +a+ is fixed at 30 (unless a stronger constraint overrides)
  #
  #  builder.formula(a) { 30 }
  #
  # +a+ is determined by the current mouse position -- note the
  # use of volatile_formula instead of formula, since the output can
  # change independently of any input variables.
  #
  #  builder.volatile_formula(a) { window.mouse_x }
  #
  # You can define multiple formulas in a single constraint (each
  # one with its own output variable), but it won't work unless the
  # formulae are legitimately interrelated.  Here's one example of
  # what is allowed:
  #
  #  builder.formula([b, c] => a) { |bv, cv| bv + cv }
  #  builder.formula([a, c] => b) { |av, cv| av - cv }
  #  builder.formula([a, b] => c) { |av, bv| av - bv }
  #
  # This constraint enforces the equality <tt>a = b + c</tt> -- note
  # how each of the output variables are used by each of the
  # formulae, and how any one of the formulae is sufficient to
  # preserve the constraint at any time.
  #
  # Here's an example of what won't work (and DeltaRed will try to
  # prevent it from being defined):
  #
  #  builder.formula(b => a) { |v| v * 2 }
  #  builder.formula(b => c) { |v| v + 1 }
  #
  # This would require DeltaRed to evaluate more than one formula
  # at a time to enforce the constraint; this second example should
  # should be expressed as two separate constraints instead.
  #
  def formula(args, &code) #:yields:*values
    case args
    when Hash
      if args.size > 1
        raise ArgumentError, "Multiple output variables not allowed"
      end
      raise ArgumentError, "No output variable given" if args.empty?
      inputs, output = args.dup.shift
      inputs = Array(inputs)
    else
      output = args
      inputs = []
    end
    if @outputs.include? output
      raise ArgumentError, "Multiple formulae per variable are not supported"
    end
    unless @methods.all? { |m| m.inputs.include? output } and
           @outputs.subset? inputs.to_set
      raise ArgumentError, "Independent outputs are not supported"
    end
    if code
      if code.arity >= 0 and inputs.size != code.arity
        raise ArgumentError, "Number of inputs must match block arity"
      end
    else
      if inputs.size == 1
        code = NOOP_PROC
      else
        code = SPLAT_PROC
      end
    end
    @outputs.add output
    @methods.push UserMethod.new(output, inputs, code)
    self
  end

  # Like formula, but defines a formula whose result may change independently
  # of its input variables.  The main difference is that it will get called
  # in response to manual recompute requests, in addition to getting called
  # when its inputs change.
  #
  # Returns +self+.
  #
  # See Constraint#volatile?, Variable#recompute, Constraint#recompute,
  # and Plan#recompute.
  #
  def volatile_formula(args, &code)
    formula(args, &code)
    @volatile = true
    self
  end

  # Builds a new Constraint based on the formulae specified so far.  The
  # constraint must be enabled with Constraint#enable before it has an
  # effect.
  def build
    raise RuntimeError, "No outputs defined" if @methods.empty?
    variables = @outputs.dup
    @methods.each { |m| variables.merge m.inputs }
    Constraint.__new__(variables.to_a, @strength, @volatile, @methods.dup)
  end

  def inspect #:nodoc:
    "#<DeltaRed::Constraint::Builder object_id=#{object_id}>"
  end
  send :alias_method, :to_s, :inspect
end

module Method #:nodoc:
  def output
    raise NotImplementedError, "#{self.class}#output not implemented"
  end

  def call
    raise NotImplementedError, "#{self.class}#call not implemented"
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

  def call
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
  attr_reader :inputs

  def initialize(output, inputs, code)
    @output = output
    @inputs = inputs
    @code = code
  end

  def call
    begin
      @output.__value__ = @code.call *@inputs.map { |i| i.value }
    rescue FormulaError => e
      @output.__deferred__ = proc { raise FormulaError, e.reason }
    rescue Exception => e
      @output.__deferred__ = proc { raise FormulaError, e }
    end
    self
  end

  def substitute(map)
    output = map[@output] || @output
    inputs = @inputs.map { |i| map[i] || i }
    UserMethod.new(output, inputs, @code)
  end
end

# A Plan provides an optimized way to recompute volatile constraints.
# Plans remain valid until a constraint reachable from the plan (i.e.
# any constraint which is connected to the plan's constraints or
# variables by other constraints) is enabled or disabled, after which
# any old plans must be discarded and new plans generated in order
# to continue producing correct updates.
#
# Note that, since it is effectively adding and removing a constraint,
# setting variables with Variable#value= can also potentially disturb
# a plan if they are part of the same constraint "network" as the plan.
#
class Plan
  class << self
    send :alias_method, :private_new, :new
    private :private_new

    def null #:nodoc:
      private_new([])
    end

    def new(*seeds)
      sources = Set.new
      for seed in seeds
        for constraint in seed.constraints
          if constraint.volatile? and constraint.enforcing_method
            sources.add constraint
          end
        end
      end
      unless sources.empty?
        private_new(sources)
      else
        NULL_PLAN
      end
    end
  end

  def initialize(sources) #:nodoc: :notnew:
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

  # Recomputes the variables covered by this plan and returns +self+.
  def recompute
    @plan.each { |method| method.call }
    self
  end

  # hide from rdoc
  send :const_set, :NULL_PLAN, Plan.null

  def inspect #:nodoc:
    "#<DeltaRed::Plan object_id=#{object_id}>"
  end
  send :alias_method, :to_s, :inspect
end

# Uses a Constraint::Builder to build a new Constraint; call
# Constraint::Builder#formula on the yielded +builder+ to
# specify how each output variable is computed.  Constraints 
# must be enabled before they have an effect.  Returns the
# new constraint.
#
# See also Constraint::Builder and Constraint#enable.
#
def self.constraint(strength=MEDIUM)
  raise ArgumentError, "No block given" unless block_given?
  Constraint.new(strength) { |builder| yield builder }
end

# Like DeltaRed.constraint, but enables the new constraint
# before returning it.
#
def self.constraint!(strength=MEDIUM)
  raise ArgumentError, "No block given" unless block_given?
  Constraint.new(strength) { |builder| yield builder }.enable
end

def self.plan_recompute(*seeds)
  Plan.new(*seeds)
end

# Creates a new input variable (a variable with a volatile
# constraint automatically added based on the passed-in block)
def self.input(&block)
  raise ArgumentError, "No block given" unless block
  variable = Variable.new
  method = UserMethod.new(variable, [], block)
  Constraint.__new__([variable], STRONG, true, [method]).enable
  variable
end

# Creates a new output constraint (a dummy constraint which
# takes a number of variables as inputs and calls the given
# block whenever they are updated).
def self.output(*variables, &block)
  raise ArgumentError, "No variables given" if variables.empty?
  raise ArgumentError, "No block given" unless block
  variable = Variable.new
  method = UserMethod.new(variable, variables, block)
  Constraint.__new__([variable, *variables], STRONG, true, [method]).enable
end

# Creates new variable objects with the given initial +values+.
# If a block is given, a new variable is created for every block
# argument; if there are more block arguments than arguments to
# DeltaRed.variables, the additional variables will be initialized
# to +nil+.
#
# Returns the result of the block if a block is given, otherwise
# it returns the created variables as an Array (unless only one
# variable is requested, in which case it just returns a single
# variable).
#
# See Variable.
#
# Examples:
#
#  a, b, c = DeltaRed.variables(1, 2, 3)
#  # a, b, and c are new Variable objects with initial values 1, 2, and 3
#
#  x = DeltaRed.variables(42)
#  # a is a new Variable object with initial value 42
#
#  DeltaRed.variables(1, 2, 3) do |a, b, c, d|
#    # a, b, and c are new Variable objects with initial values 1, 2, and 3
#    # d is a new Variable object with the initial value nil
#  end
#
def self.variables(*values, &block)
  count = values.size
  count = block.arity if block and block.arity > values.size
  raise ArgumentError, "No variables requested" if count.zero?
  variables = Array.new(count)
  (0...count).zip(values) { |i, v| variables[i] = Variable.new(v) }
  if block
    block.call *variables
  elsif count == 1
    variables.first
  else
    variables
  end
end

end

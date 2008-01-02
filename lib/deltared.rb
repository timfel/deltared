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

# This implementation is very closely based on the pseudocode presented in
# the appendix of "Multi-way versus One-way Constraints in User Interfaces:
# Experience with the DeltaBlue Algorithm" by Sannella et al., available at
# http://citeseer.ist.psu.edu/sannella93multiway.html
#
module DeltaRed

class Mark #:nodoc:
end 

REQUIRED = 4
STRONG   = 3
MEDIUM   = 2
WEAK     = 1
WEAKEST  = 0

class Variable
  attr_reader   :value
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

  def initialize(value)
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
      variable = todo.find { true }
      todo.delete variable
      for constraint in variable.constraints
        unenforced.add constraint unless constraint.enforcing_method
      end
      for constraint in variable.consuming_constraints
        constraint.recalculate
        todo.add constraint.enforcing_method.output
      end
    end
    # sort by decreasing strength
    unenforced.to_a.sort! { |a, b| b.strength <=> a.strength }
  end

  def consuming_constraints #:nodoc:
    @constraints.select { |c|
      c.enforcing_method and c != @determined_by
    }.to_set
  end

  def marked?(mark) #:nodoc:
    @mark.eql? mark
  end

  def value=(value)
    unless @edit_constraint
      edit_method = EditMethod.new(self, value)
      @edit_constraint = Constraint.__new__([self], REQUIRED,
                                            false, [edit_method])
    else
      @edit_constraint.methods.first.value = value
    end
    @edit_constraint.enable.disable
    value
  end
end

class Namespace
  def initialize
    @variables = {}
  end

  def [](name)
    @variables[name.to_sym] ||= Variable.new
  end
end

class Constraint
  attr_reader :enabled
  attr_reader :variables
  attr_reader :strength
  attr_reader :external_input
  attr_reader :methods          #:nodoc:
  attr_reader :enforcing_method #:nodoc:

  class << self
    send :alias_method, :__new__, :new
    def build(strength=MEDIUM, external_input=false)
      raise ArgumentError, "No block given" unless block_given?
      builder = Builder.new(strength, external_input)
      yield builder
      builder.build
    end
    alias new build
  end

  alias external_input? external_input
  alias enabled? enabled

  def initialize(variables, strength, external_input, methods) #:nodoc:
    @variables = variables.freeze
    @strength = strength
    @external_input = external_input
    @methods = methods.freeze
    @enforcing_method = nil
    @enabled = false
  end

  def substitute(map)
    variables = variables.map { |v| map[v] || v }.uniq
    methods = methods.map { |m| m.substitute(map) }
    Constraint.__new__(variables, @strength, @external_input, methods)
  end

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
      constraint = todo.find { true }
      todo.delete constraint
      if constraint.enforcing_method.output.marked? mark
        constraint.incremental_remove
        raise RuntimeError, "Cycle encountered"
      end
      constraint.recalculate
      todo.merge constraint.enforcing_method.output.consuming_constraints
    end
    self
  end

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

  def recalculate #:nodoc:
    output = @enforcing_method.output
    output.walk_strength = output_walk_strength
    stay = output.stay = constant_output?
    @enforcing_method.execute if stay
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

  def compute(args, &code)
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

  def bulid #:nodoc:
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

class Plan
  class << self
    private :new

    def new_from_variables(*variables)
      sources = Set.new
      for variable in variables
        for constraint in variable.constraints
          if constraint.external_input? and constraint.enforcing_method
            sources.add constraint
          end
        end
      end
      new(sources)
    end

    def new_from_constraints(*constraints)
      sources = Set.new
      for constraint in constraints
        if constraint.external_input? and constraint.enforcing_method
          sources.add constraint
        end
      end
      new(sources)
    end
  end

  def initialize(sources) #:nodoc:
    @plan = []
    mark = Mark.new
    hot = sources
    until hot.empty?
      constraint = hot.find { true }
      hot.delete constraint
      output = constraint.enforcing_method.output
      if not output.marked? mark and constraint.inputs_known?(mark)
        @plan.push constraint
        output.mark mark
        hot.merge output.consuming_constraints
      end
    end
  end

  def execute
    for constraint in @plan
      constraint.enforcing_method.execute
    end
    self
  end
end

def self.namespace
  ns = Namespace.new
  if block_given?
    yield ns
  else
    ns
  end
end

def self.constraint(strength=STRONG, external_input=false)
  raise ArgumentError, "No block given" unless block_given?
  Constraint.new(strength, external_input) { |builder| yield builder }
end

end

# DeltaRed - an implementation of the DeltaBlue algorithm
#
# Copyright 2007  MenTaLguY <mental@rydia.net>
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
  attr_accessor :value
  attr_reader   :constraints   #:nodoc:
  attr_accessor :determined_by #:nodoc:
  attr_accessor :walk_strength #:nodoc:
  attr_accessor :mark          #:nodoc:
  attr_accessor :stay          #:nodoc:
  alias stay? stay             #:nodoc:

  def initialize(value)
    @value = value
    @constraints = Set.new
    @determined_by = nil
    @walk_strength = WEAKEST
    @mark = nil
    @stay = true
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
end

class Constraint
  attr_reader :variables
  attr_reader :strength
  attr_reader :input
  attr_reader :methods
  attr_reader :enforcing_method #:nodoc:

  alias input? input

  def initialize(is_input, strength, *methods)
    raise ArgumentError, "No methods specified" if methods.empty?
    @variables = methods.map { |m| [ m.output, *m.inputs ] }.flatten.uniq
    @strength = strength
    @input = is_input
    @methods = methods
    @enforcing_method = nil
  end

  def add
    @enforcing_method = nil
    for variable in @variables
      variable.constraints.add self
    end
    incremental_add
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
      inputs.each { |v| v.mark = mark }
      output = @enforcing_method.output
      retracted = output.determined_by
      retracted.unenforce if retracted
      output.determined_by = self
      add_propagate(mark)
      @enforcing_method.output.mark = mark
      retracted
    else
      if @strength == REQUIRED
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
      if output.mark != mark and output.walk_strength < weakest_strength
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
      if constraint.enforcing_method.output.mark == mark
        constraint.incremental_remove
        raise RuntimeError, "Cycle encountered"
      end
      constraint.recalculate
      todo.merge constraint.enforcing_method.output.consuming_constraints
    end
    self
  end

  def remove
    if @enforcing_method
      incremental_remove
    else
      for variable in @variables
        variable.constraints.delete self
      end
    end
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
    inputs.all? { |v| v.mark == mark or v.stay? }
  end

  def recalculate #:nodoc:
    output = @enforcing_method.output
    output.walk_strength = output_walk_strength
    stay = output.stay = constant_output?
    @enforcing_method.execute if stay
    self
  end

  def constant_output? #:nodoc:
    not input? and inputs.all? { |v| v.stay? }
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

class Method
  attr_reader :output
  attr_reader :inputs

  def initialize(output, *inputs, &code)
    raise ArgumentError, "Block expected" unless code
    @output = output
    @inputs = inputs
    @code = code
  end

  def execute
    @output.value = @code.call *@inputs.map { |i| i.value }
    self
  end
end

class Plan
  class << self
    private :new

    def new_from_variables(*variables)
      sources = Set.new
      for variable in variables
        for constraint in variable.constraints
          sources.add constraint if constraint.input? and constraint.enforcing_method
        end
      end
      new(sources)
    end

    def new_from_constraints(*constraints)
      sources = Set.new
      for constraint in constraints
        sources.add constraint if constraint.input? and constraint.enforcing_method
      end
      new(sources)
    end
  end

  def initialize(sources)
    @plan = []
    mark = Mark.new
    hot = sources
    until hot.empty?
      constraint = hot.find { true }
      hot.delete constraint
      output = constraint.enforcing_method.output
      if output.mark != mark and constraint.inputs_known?(mark)
        @plan << constraint
        output.mark = mark
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

end

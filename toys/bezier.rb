# bezier - a deltared toy
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

$:.push(File.join(File.dirname($0)))
$:.push(File.join(File.dirname($0), "..", "lib"))
require 'toy'
require 'deltared'

class Bezier
  attr_reader :inputs
  attr_reader :endpoints
  attr_reader :velocities
  attr_reader :outputs

  def initialize(c0, c1, c2, c3)
    @inputs = DeltaRed.variables(c0, c1, c2, c3)
    @velocities = DeltaRed.variables(nil, nil)
    @endpoints = [inputs[0], inputs[3]]
    @outputs = [inputs[0]] + DeltaRed.variables(nil, nil) + [inputs[3]]

    (0..1).each do |i|
      endpoint = inputs[i*3]
      velocity = velocities[i]
      sign = 1 - 2 * i
      velocity.constraint!(inputs[i+1]) do |h|
        rel_to = endpoint.value
        [ sign * ( h[0] - rel_to[0] ), sign * ( h[1] - rel_to[1] ) ]
      end
      outputs[i+1].constraint!(endpoint, velocity) do |h, v|
        [ h[0] + sign * v[0], h[1] + sign * v[1] ]
      end
    end
  end

  def draw_bezier(toy)
    bezier = toy.draw {}
    DeltaRed.output(*outputs) do |(x0, y0), (x1, y1), (x2, y2), (x3, y3)|
      bezier.redraw do |ctx|
        ctx.clear_path
        ctx.move_to x0, y0
        ctx.curve_to x1, y1, x2, y2, x3, y3
        ctx.stroke_rgb 2, 0.0, 0.0, 0.9
        ctx.clear_path
        ctx.move_to x0, y0
        ctx.line_to x1, y1
        ctx.move_to x2, y2
        ctx.line_to x3, y3
        ctx.stroke_rgb 1, 0.0, 0.0, 0.0
      end
    end
    self
  end

  def draw_handles(toy)
    inputs.zip(outputs) do |input, output|
      handle = toy.knot(*output.value) { |x, y| input.value = [x, y] }
      DeltaRed.output(output) { |x, y| handle.move(x, y) }
    end
    self
  end
end

Toy.run("Bezier") do |toy|
  beziers = [[[10, 100], [30, 100], [40, 20], [60, 20]],
             [[60, 20], [80, 20], [90, 100], [110, 100]]].map \
  { |nodes|
    Bezier.new(*nodes)
  }
  DeltaRed.constraint! do |c|
    c.formula(beziers.first.endpoints.last => beziers.last.endpoints.first)
    c.formula(beziers.last.endpoints.first => beziers.first.endpoints.last)
  end
  DeltaRed.constraint! do |c|
    c.formula(beziers.first.velocities.last => beziers.last.velocities.first)
    c.formula(beziers.last.velocities.first => beziers.first.velocities.last)
  end
  beziers.each { |b| b.draw_bezier(toy) }
  beziers.each { |b| b.draw_handles(toy) }
end

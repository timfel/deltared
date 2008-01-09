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

Toy.run("Bezier") do
  inputs = DeltaRed.variables([10, 50], [50, 60], [60, 40], [100, 50])
  velocities = DeltaRed.variables(nil, nil)
  outputs = [inputs[0]] + DeltaRed.variables(nil, nil) + [inputs[3]]

  (0..1).each do |i|
    endpoint = inputs[i*3]
    velocity = velocities[i]
    velocity.constraint!(inputs[i+1]) do |h|
      rel_to = endpoint.value
      [ h[0] - rel_to[0], h[1] - rel_to[1] ]
    end
    outputs[i+1].constraint!(endpoint, velocity) do |h, v|
      [ h[0] + v[0], h[1] + v[1] ]
    end
  end

  bezier = draw {}
  DeltaRed.output(*outputs) do |(x0, y0), (x1, y1), (x2, y2), (x3, y3)|
    bezier.redraw do |ctx|
      ctx.move_to x0, y0
      ctx.curve_to x1, y1, x2, y2, x3, y3
      ctx.stroke_rgb 2, 0.0, 0.0, 0.9
      ctx.move_to x0, y0
      ctx.line_to x1, y1
      ctx.move_to x2, y2
      ctx.line_to x3, y3
      ctx.stroke_rgb 1, 0.0, 0.0, 0.0
    end
  end

  inputs.zip(outputs) do |input, output|
    handle = knot(*output.value) { |x, y| input.value = [x, y] }
    DeltaRed.output(output) { |x, y| handle.move(x, y) }
  end
end

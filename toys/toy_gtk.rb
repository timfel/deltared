# toy - a simple API for trivial demo applications
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

require 'toy_gtk'

class Toy
  class << self
    private :new
    def run(*args, &block)
      Impl.right_away do
        new(*args).instance_eval &block
      end
    end
  end

  class Window
    def initialize(title)
      @window = Impl::Window.new(title)
      @graphics = []
      @grabbed = nil
      @window.draw do |ctx|
        ctx.clear_rgb 1.0, 0.95, 0.9
        @graphics.each { |g| g.draw ctx }
      end
      @window.pressed do |x, y|
        hit = @graphics.reverse.find { |g| g.hit?(x, y) }
        if hit
          @grabbed = hit
          @window.grab
        end
      end
      @window.dragged do |x, y|
        @grabbed.dragged(x, y) if @grabbed
      end
      @window.released do
        @window.ungrab if @grabbed
        @grabbed = nil
      end
    end

    def clear_graphics
      @graphics.clear
      if @grabbed
        @window.ungrab
        @grabbed = nil
      end
      @window.queue_redraw
      self
    end

    def add_graphic(graphic, before=nil)
      if before
        index = @graphics.index before_graphic
      else
        index = nil
      end
      if index
        @graphics[index, 0] = graphic
      else
        @graphics.push graphic
      end
      @window.queue_redraw
      self
    end

    def delete_graphic(graphic)
      @graphics.delete graphic
      if @grabbed = graphic
        @window.ungrab
        @grabbed = nil
      end
      @window.queue_redraw
      self
    end
  end

  class Graphic
    attr_reader :parent
    attr_reader :x
    attr_reader :y
    attr_reader :graphic

    def initialize(parent)
      @x = 0
      @y = 0
      @draw = nil
      @when_dragged = nil
      @hit_test = nil
      @hidden = false
    end

    def remove
      @parent.delete_graphic self
      self
    end

    def move(x, y)
      x = x.to_i
      y = y.to_i
      if @x != x or @y != y
        @x = x
        @y = y
        @parent.queue_redraw
      end
      self
    end

    def draw(ctx)
      if @draw
        ctx.group do
          ctx.translate @x, @y
          @draw.call(ctx)
        end
      end
      self
    end

    def dragged(x, y)
      @when_dragged.call(x, y) if @when_dragged
      self
    end

    def hit?(x, y)
      if @hit_test
        not @hidden and @hit_test.call(x, y)
      else
        false
      end 
    end

    def show
      @hidden = false
      @parent.queue_redraw
      self
    end

    def hide
      @hidden = true
      @parent.queue_redraw
      self
    end

    def hidden? ; @hidden ; end

    def redraw(&block)
      if not @hidden and ( not block or @draw != block )
        @draw = block if block
        @parent.queue_redraw
      end
      self
    end

    def when_dragged(&block)
      @when_dragged = block
      self
    end

    def hit_test(&block)
      @hit_test = block
      self
    end
  end

  def initialize(title="Toy")
    @toy_window = Window.new(title)
  end

  def clear(&block)
    @toy_window.clear_graphics
    draw(&block) if block
    self
  end

  def draw(&block)
    raise ArgumentError, "No block given" unless block
    graphic = Graphic.new(@toy_window)
    graphic.redraw(&block)
    @toy_window.add_graphic(graphic)
    self
  end

  def knot(x, y, &block)
    graphic = Graphic.new(@toy_window)
    block = proc { |x, y| graphic.move(x, y) } unless block
    graphic.when_dragged(&block)
    graphic.redraw do |ctx|
      ctx.clear_path
      ctx.move_to -5, -5
      ctx.line_to 5, -5
      ctx.line_to 5, 5
      ctx.line_to -5, 5
      ctx.close_path
      ctx.stroke_rgb 1, 0.0, 0.5, 0.0
    end
    graphic.hit_test do |x, y|
      (self.x - x).abs >= 5 and (self.y - y).abs >= 5
    end
    graphic.move(x, y)
    @toy_window.add_graphic(graphic)
    self
  end
end

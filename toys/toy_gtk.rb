# toy_gtk - a simple API for trivial demo applications (Gtk backend)
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

require 'gtk2'

Gtk.init

class Toy
module Impl

@initted = false

def self.run(&block)
  exception = nil
  GLib::Idle.add do
    begin
      block.call
    rescue Exception => exception
      Gtk.main_quit
    end
    false
  end
  Gtk.main
  raise exception if exception
end

class RenderContext
  def initialize(cairo)
    @cairo = cairo
  end

  def translate(x, y)
    @cairo.translate(x, y)
    self
  end

  def clear_path
    @cairo.new_path
    self
  end

  def move_to(x, y)
    @cairo.move_to(x, y)
    self
  end

  def line_to(x, y)
    @cairo.line_to(x, y)
    self
  end

  def curve_to(x0, y0, x1, y1, x2, y2)
    @cairo.curve_to(x0, y0, x1, y1, x2, y2)
    self
  end

  def close_path
    @cairo.close_path
    self
  end

  def clear_rgb(r, g, b)
    @cairo.set_source_rgb(r, g, b)
    @cairo.paint
    self
  end

  def stroke_rgb(width, r, g, b)
    @cairo.line_width = width
    @cairo.set_source_rgb(r, g, b)
    @cairo.stroke_preserve
    self
  end

  def fill_rgb(width, r, g, b)
    @cairo.set_source_rgb(r, g, b)
    @cairo.fill_preserve
    self
  end

  def group
    begin
      @cairo.save
      yield
    ensure
      @cairo.restore
    end
  end
end

class Widget
  def initialize(widget)
    @widget = widget
  end

  def show
    @widget.show
    self
  end

  def hide
    @widget.hide
    self
  end

  def hidden=(hide)
    if hide
      @widget.hide
    else
      @widget.show
    end
    self
  end

  def hidden? ; not @widget.visible? ; end

  def enable
    @widget.sensitive = true
    self
  end

  def disable
    @widget.sensitive = false
    self
  end

  def enabled=(enable)
    @widget.sensitive = !!enable
    self
  end

  def enabled? ; @widget.sensitive? ; end
end

class Button < Widget
  def initialize(widget)
    super(widget)
    @connection = nil
  end

  def label ; @widget.label ; end
  def label=(label) ; @widget.label = label ; end

  def when_clicked(&block)
    @widget.signal_handler_disconnect @connection if @connection
    if block
      @connection = @widget.signal_connect('clicked') { block.call }
    else
      @connection = nil
    end
    self
  end
end

class Window
  def initialize(title)
    @toplevel = Gtk::Window.new
    @toplevel.title = title

    content_box = Gtk::VBox.new
    @toplevel.add content_box

    @controls = Gtk::HBox.new
    content_box.pack_start @controls, false

    @canvas = Gtk::DrawingArea.new
    content_box.pack_start @canvas, true, true

    @toplevel.show_all

    @toplevel.signal_connect('delete_event') { Gtk.main_quit ; false }
    @draw = nil
    @press = nil
    @drag = nil
    @release = nil
    @canvas.signal_connect('expose_event') do
      if @draw
        ctx = RenderContext.new @canvas.window.create_cairo_context
        @draw.call ctx 
      end
    end
    @canvas.signal_connect('button_press_event') do |_, event|
      if @press and event.button = 1 and event.event_type == Gdk::Event::BUTTON_PRESS
        @press.call event.x.to_i, event.y.to_i
      end
    end
    @canvas.signal_connect('motion_notify_event') do |_, event|
      if @drag and ( event.state & Gdk::Window::BUTTON1_MASK ).nonzero?
        @drag.call event.x.to_i, event.y.to_i
      end
    end
    @canvas.signal_connect('button_release_event') do |_, event|
      if @press and event.button = 1 and event.event_type == Gdk::Event::BUTTON_RELEASE
        @release.call event.x.to_i, event.y.to_i
      end
    end
    @canvas.add_events(Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::BUTTON_RELEASE_MASK | Gdk::Event::BUTTON1_MOTION_MASK)
  end

  def queue_redraw
    w = @canvas.window
    return self unless w
    x, y, width, height = w.geometry
    rect = Gdk::Rectangle.new(0, 0, width, height)
    w.invalidate rect, false
    self
  end

  def add_button(label, &block)
    widget = Gtk::Button.new
    button = Button.new(widget)
    button.label = label
    button.when_clicked(&block)
    button.show
    @controls.pack_start(widget, false, false, 2)
    button
  end

  def grab
    w = @canvas.window
    return self unless w
    Gdk.pointer_grab(w, false, @canvas.events, nil, nil, Gdk::Event::CURRENT_TIME)
    self
  end

  def ungrab
    Gdk.pointer_ungrab(Gdk::Event::CURRENT_TIME)
    self
  end

  def draw(&block)
    @draw = block
    queue_redraw
    self
  end

  def press(&block)
    @press = block
    self
  end

  def drag(&block)
    @drag = block
    self
  end

  def release(&block)
    @release = block
    self
  end
end

end
end

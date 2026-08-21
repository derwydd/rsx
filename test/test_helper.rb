# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "rsx"

module RSXTest
  def setup
    RSX.reset!
    # Compile in memory so tests never touch the filesystem cache.
    RSX.config.cache_dir = nil
    RSX.config.paths = [File.expand_path("fixtures", __dir__)]
  end

  def teardown
    Array(@defined_constants).each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
    RSX.reset!
  end

  # Renders .rsx source as a template.
  def render(source, **props)
    RSX.render_source(source, **props).to_s
  end

  def compile(source)
    RSX.compile(source)
  end

  # Evaluates .rsx source for its `component` definitions and returns the
  # constant named by `name`. Defined constants are removed after each test.
  def define(source, name: nil)
    RSX::Template.new(source).component.new.rsx_render(nil)
    (@defined_constants ||= []) << name.to_s.split("::").first if name
    name ? Object.const_get(name) : nil
  end
end

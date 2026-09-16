# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "uri" # ActionView 7.1 looks up URI without requiring it
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

  # Rails is optional, so its tests skip when it is not installed. CI sets
  # RSX_REQUIRE_RAILS for the runs that do install it, where a skip would mean
  # the whole Rails suite had quietly stopped running.
  def require_rails!(available, what)
    return if available

    flunk "#{what} was expected but could not be loaded" if ENV["RSX_REQUIRE_RAILS"].to_s != ""
    skip "#{what} is not installed"
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

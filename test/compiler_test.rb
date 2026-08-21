# frozen_string_literal: true

require "test_helper"

# Properties of the generated Ruby itself.
class CompilerTest < Minitest::Test
  include RSXTest

  def test_static_markup_becomes_one_string_literal
    ruby = compile(%(<div className="card"><h1>Title</h1><p>Body</p></div>))

    assert_includes ruby, %(<div class=\\"card\\"><h1>Title</h1><p>Body</p></div>)
    assert_equal 1, ruby.scan("::RSX.static").length
  end

  def test_dynamic_markup_keeps_static_text_inline
    ruby = compile("<div><h1>Title</h1><p>{name}</p></div>")

    assert_includes ruby, %(<div><h1>Title</h1><p>)
    assert_includes ruby, "::RSX.child((name))"
    refute_includes ruby, "::RSX.static"
  end

  def test_generated_ruby_has_the_same_number_of_lines
    source = <<~RSX
      component Multi do |props|
        return (
          <section>
            <h1>
              {props[:title]}
            </h1>
            <p>tail</p>
          </section>
        )
      end
    RSX

    assert_equal source.lines.length, compile(source).lines.reject { |l| l.start_with?("# rsx:") }.length
  end

  def test_backtrace_points_at_the_source_line
    source = <<~RSX
      <div>
        <p>fine</p>
        {raise "kaboom"}
      </div>
    RSX

    error = assert_raises(RuntimeError) { render(source) }
    frame = error.backtrace.find { |line| line.include?("(rsx)") }

    refute_nil frame, "expected a backtrace frame from the template"
    assert_match(/\(rsx\):3/, frame)
  end

  def test_backtrace_inside_a_component_points_at_the_source_line
    source = <<~RSX
      component Broken do |props|
        value = 1

        return (
          <div>
            {value.no_such_method}
          </div>
        )
      end
    RSX

    component = define(source, name: "Broken")
    error = assert_raises(NoMethodError) { component.call.to_s }
    frame = error.backtrace.find { |line| line.include?("(rsx)") }

    refute_nil frame
    assert_match(/\(rsx\):6/, frame)
  end

  def test_component_marker_is_only_added_for_component_files
    assert RSX::Transformer.defines_components?(compile("component A do |p|\n  return <p>a</p>\nend\n"))
    refute RSX::Transformer.defines_components?(compile("<p>a</p>\n"))
  end

  def test_import_and_export_statements_compile_to_calls
    ruby = compile(%(import Button from "widgets/button"\nexport default Button\n))

    assert_includes ruby, %(::RSX.import("widgets/button", as: %i[Button], from: __FILE__))
    assert_includes ruby, "::RSX.export_default(Button, from: __FILE__)"
  end

  def test_import_list_form
    ruby = compile(%(import { Card, Badge } from "ui"\n))
    assert_includes ruby, %(::RSX.import("ui", as: %i[Card Badge], from: __FILE__))
  end

  def test_bare_import
    ruby = compile(%(import "ui/setup"\n))
    assert_includes ruby, %(::RSX.import("ui/setup", from: __FILE__))
  end

  def test_component_options_are_passed_through
    ruby = compile("component A, cache: { expires_in: 60 } do |props|\n  return <p>a</p>\nend\n")
    assert_includes ruby, %(::RSX.define_component("A", cache: { expires_in: 60 }))
  end

  def test_component_without_parameters
    ruby = compile("component A do\n  return <p>a</p>\nend\n")
    assert_includes ruby, "def rsx_render(_props = nil)"
  end
end

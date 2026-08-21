# frozen_string_literal: true

require "test_helper"

# The scanner has to tell markup apart from Ruby's use of "<" and has to leave
# every other kind of Ruby literal alone.
class RubySyntaxTest < Minitest::Test
  include RSXTest

  def test_less_than_is_not_markup
    assert_equal "<p>yes</p>", render(%(<p>{1 < 2 ? "yes" : "no"}</p>))
  end

  def test_comparison_chain
    assert_equal "<p>true</p>", render("<p>{((1 < 2) && (3 > 2)).to_s}</p>")
  end

  def test_and_shortcut_renders_conditionally
    # The React idiom: a false left-hand side renders nothing.
    assert_equal "<div><b>on</b></div>", render("<div>{props[:on] && <b>on</b>}</div>", on: true)
    assert_equal "<div></div>", render("<div>{props[:on] && <b>on</b>}</div>", on: false)
  end

  # Every {ruby} container starts in expression position, no matter what the
  # container before it left behind.
  def test_sibling_expression_containers_are_independent
    html = render(<<~RSX)
      <div>
        <a href={"/one"}>one</a>
        <b title={"t"}>{<i>two</i>}</b>
        <p>{"a" if 1 < 2}</p>
      </div>
    RSX

    assert_equal %(<div><a href="/one">one</a><b title="t"><i>two</i></b><p>a</p></div>), html
  end

  def test_shovel_operator
    assert_equal "<p>ab</p>", render(%(<p>{(+"a") << "b"}</p>))
  end

  def test_spaceship_operator
    assert_equal "<p>-1</p>", render("<p>{1 <=> 2}</p>")
  end

  def test_less_than_or_equal
    assert_equal "<p>true</p>", render("<p>{(1 <= 1).to_s}</p>")
  end

  def test_class_definition_with_superclass_is_left_alone
    ruby = compile("class Widget < String\nend\n<p>x</p>\n")
    assert_includes ruby, "class Widget < String"
  end

  def test_anonymous_class_with_superclass
    source = <<~RSX
      klass = Class.new(String) do
        def label = "w"
      end
      <p>{klass.new.label}</p>
    RSX
    assert_equal "<p>w</p>", render(source)
  end

  def test_singleton_class_syntax
    source = <<~RSX
      klass = Class.new do
        class << self
          def label = "meta"
        end
      end
      <p>{klass.label}</p>
    RSX
    assert_equal "<p>meta</p>", render(source)
  end

  def test_markup_inside_a_string_is_left_alone
    assert_equal "<p>&lt;div&gt;</p>", render(%(<p>{"<div>"}</p>))
  end

  def test_squiggly_heredoc
    source = <<~RSX
      text = <<~HTML
        <div>not markup</div>
      HTML
      <p>{text.strip}</p>
    RSX
    assert_equal "<p>&lt;div&gt;not markup&lt;/div&gt;</p>", render(source)
  end

  def test_heredoc_after_a_method_call
    source = <<~RSX
      value = String(<<~TEXT)
        <b>plain</b>
      TEXT
      <p>{value.strip}</p>
    RSX
    assert_equal "<p>&lt;b&gt;plain&lt;/b&gt;</p>", render(source)
  end

  def test_regexp_literal
    assert_equal "<p>0</p>", render(%(<p>{("<a>" =~ /<a>/)}</p>))
  end

  def test_percent_literals
    assert_equal "<p>&lt;a&gt; &lt;b&gt;</p>", render(%(<p>{%w[<a> <b>].join(" ")}</p>))
  end

  def test_comments_are_ignored
    source = <<~RSX
      # <div>this is a comment</div>
      <p>ok</p>
    RSX
    assert_equal "<p>ok</p>", render(source)
  end

  def test_block_comment
    source = <<~RSX
      =begin
      <div>documentation</div>
      =end
      <p>ok</p>
    RSX
    assert_equal "<p>ok</p>", render(source)
  end

  def test_string_interpolation_containing_markup
    assert_equal "<p><i>x</i></p>", render(%q[<p>{RSX.raw("#{<i>x</i>}")}</p>])
  end

  def test_symbols_and_hashes
    assert_equal "<p>1</p>", render(%(<p>{{ a: 1 }[:a]}</p>))
  end

  def test_ternary_with_markup_on_both_sides
    assert_equal "<b>yes</b>", render("<>{true ? <b>yes</b> : <i>no</i>}</>")
  end

  def test_markup_in_a_method_argument
    assert_equal "<p><b>x</b></p>", render("<p>{RSX.child(<b>x</b>)}</p>")
  end

  def test_markup_assigned_to_a_local
    source = <<~RSX
      badge = <span className="badge">new</span>
      <p>{badge}</p>
    RSX
    assert_equal %(<p><span class="badge">new</span></p>), render(source)
  end

  def test_markup_in_an_array_literal
    source = <<~RSX
      items = [<li>a</li>, <li>b</li>]
      <ul>{items}</ul>
    RSX
    assert_equal "<ul><li>a</li><li>b</li></ul>", render(source)
  end

  def test_conditional_statement
    source = <<~RSX
      if props[:admin]
        <p>admin</p>
      else
        <p>guest</p>
      end
    RSX
    assert_equal "<p>admin</p>", render(source, admin: true)
    assert_equal "<p>guest</p>", render(source, admin: false)
  end

  def test_statement_modifier_does_not_open_a_block
    source = <<~RSX
      component ModifierCase do |props|
        return <p>short</p> if props[:short]

        <p>long</p>
      end
    RSX
    component = define(source, name: "ModifierCase")
    assert_equal "<p>short</p>", component.call(short: true).to_s
    assert_equal "<p>long</p>", component.call(short: false).to_s
  ensure
    Object.send(:remove_const, :ModifierCase) if defined?(ModifierCase)
  end

  def test_case_when_and_loops
    source = <<~RSX
      component Mixed do |props|
        label = case props[:kind]
                when :a then "A"
                else "other"
                end

        rows = []
        props[:count].times do |index|
          rows << <li>{index}</li>
        end

        while rows.length > 2
          rows.pop
        end

        return (
          <div>
            <h1>{label}</h1>
            <ul>{rows}</ul>
          </div>
        )
      end
    RSX
    component = define(source, name: "Mixed")
    assert_equal "<div><h1>A</h1><ul><li>0</li><li>1</li></ul></div>",
                 component.call(kind: :a, count: 5).to_s
  ensure
    Object.send(:remove_const, :Mixed) if defined?(Mixed)
  end

  def test_endless_method_inside_a_component
    source = <<~RSX
      component Endless do |props|
        def shout(text) = text.upcase

        return <p>{shout("hi")}</p>
      end
    RSX
    component = define(source, name: "Endless")
    assert_equal "<p>HI</p>", component.call.to_s
  ensure
    Object.send(:remove_const, :Endless) if defined?(Endless)
  end

  def test_begin_rescue_inside_a_component
    source = <<~RSX
      component Risky do |props|
        message = begin
          raise "boom"
        rescue => error
          error.message
        end

        return <p>{message}</p>
      end
    RSX
    component = define(source, name: "Risky")
    assert_equal "<p>boom</p>", component.call.to_s
  ensure
    Object.send(:remove_const, :Risky) if defined?(Risky)
  end

  def test_unterminated_element_reports_a_syntax_error
    error = assert_raises(RSX::SyntaxError) { compile("<div><p>oops</div>") }
    assert_match(/does not match/, error.message)
  end

  def test_mismatched_closing_tag_names_the_tags
    error = assert_raises(RSX::SyntaxError) { compile("<div>x</span>") }
    assert_match(%r{</span>.*<div>}, error.message)
  end

  def test_spread_without_splat_is_rejected
    error = assert_raises(RSX::SyntaxError) { compile("<div {props}></div>") }
    assert_match(/\{\*\*props\}/, error.message)
  end

  def test_lowercase_component_name_is_rejected
    error = assert_raises(RSX::SyntaxError) { compile("component my_thing do |props|\nend") }
    assert_match(/must be constants/, error.message)
  end
end

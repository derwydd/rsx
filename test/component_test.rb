# frozen_string_literal: true

require "test_helper"

class ComponentTest < Minitest::Test
  include RSXTest

  def test_keyword_props_with_defaults
    component = define(<<~'RSX', name: "Button")
      component Button do |label:, variant: "primary"|
        return <button className={"btn btn-#{variant}"}>{label}</button>
      end
    RSX

    assert_equal %(<button class="btn btn-primary">Save</button>), component.call(label: "Save").to_s
    assert_equal %(<button class="btn btn-danger">Delete</button>),
                 component.call(label: "Delete", variant: "danger").to_s
  end

  def test_positional_props_hash
    component = define(<<~RSX, name: "Title")
      component Title do |props|
        return <h1>{props[:text]}</h1>
      end
    RSX

    assert_equal "<h1>Hi</h1>", component.call(text: "Hi").to_s
  end

  def test_props_reader_is_available_in_keyword_style
    component = define(<<~RSX, name: "Both")
      component Both do |name:|
        return <p>{name} {props[:name]}</p>
      end
    RSX

    assert_equal "<p>a a</p>", component.call(name: "a").to_s
  end

  def test_component_tag_renders_a_component
    define(<<~RSX, name: "Badge")
      component Badge do |text:|
        return <span className="badge">{text}</span>
      end
    RSX

    assert_equal %(<p><span class="badge">new</span></p>), render(%(<p><Badge text="new" /></p>))
  end

  def test_children_are_passed_to_the_component
    define(<<~RSX, name: "Card")
      component Card do |title:, children: nil|
        return (
          <section className="card">
            <h2>{title}</h2>
            <div className="body">{children}</div>
          </section>
        )
      end
    RSX

    html = render(%(<Card title="Hello"><p>Body</p></Card>))
    assert_equal %(<section class="card"><h2>Hello</h2><div class="body"><p>Body</p></div></section>), html
  end

  def test_children_are_lazy_and_rendered_once
    counter = { renders: 0 }
    Object.const_set(:RSXCounter, counter)
    define(<<~RSX, name: "Twice")
      component Twice do |children: nil|
        return <div>{children}{children}</div>
      end
    RSX

    html = render("<Twice>{RSXCounter[:renders] += 1}</Twice>")
    assert_equal "<div>11</div>", html
    assert_equal 1, counter[:renders]
  ensure
    Object.send(:remove_const, :RSXCounter) if Object.const_defined?(:RSXCounter, false)
  end

  def test_component_can_ignore_children
    define(<<~RSX, name: "Ignores")
      component Ignores do |children: nil|
        return <p>nothing</p>
      end
    RSX

    assert_equal "<p>nothing</p>", render(%(<Ignores>{raise "never evaluated"}</Ignores>))
  end

  def test_children_predicate
    define(<<~RSX, name: "Maybe")
      component Maybe do |children: nil|
        return <div>{children? ? children : "empty"}</div>
      end
    RSX

    assert_equal "<div>x</div>", render("<Maybe>x</Maybe>")
    assert_equal "<div>empty</div>", render("<Maybe />")
  end

  def test_undeclared_children_are_dropped_rather_than_raising
    define(<<~RSX, name: "NoKids")
      component NoKids do |label:|
        return <p>{label}</p>
      end
    RSX

    assert_equal "<p>hi</p>", render(%(<NoKids label="hi">ignored</NoKids>))
  end

  def test_unknown_prop_raises_props_error
    component = define(<<~RSX, name: "Strict")
      component Strict do |label:|
        return <p>{label}</p>
      end
    RSX

    error = assert_raises(RSX::PropsError) { component.call(label: "x", oops: 1).to_s }
    assert_match(/does not accept :oops/, error.message)
  end

  def test_missing_required_prop_raises_props_error
    component = define(<<~RSX, name: "Needy")
      component Needy do |label:|
        return <p>{label}</p>
      end
    RSX

    error = assert_raises(RSX::PropsError) { component.call.to_s }
    assert_match(/missing keyword/, error.message)
  end

  def test_rest_props_are_accepted_and_spreadable
    define(<<~RSX, name: "Passthrough")
      component Passthrough do |label:, **rest|
        return <button {**rest}>{label}</button>
      end
    RSX

    html = render(%(<Passthrough label="Go" id="go" className="btn" />))
    assert_equal %(<button id="go" class="btn">Go</button>), html
  end

  def test_props_can_be_spread_into_a_component
    define(<<~RSX, name: "Greet")
      component Greet do |first:, last:|
        return <p>{first} {last}</p>
      end
    RSX

    source = <<~RSX
      person = { first: "Ada", last: "Lovelace" }
      <Greet {**person} />
    RSX
    assert_equal "<p>Ada Lovelace</p>", render(source)
  end

  def test_markup_can_be_passed_as_a_prop
    define(<<~RSX, name: "Panel")
      component Panel do |header:, children: nil|
        return <div><header>{header}</header>{children}</div>
      end
    RSX

    html = render("<Panel header={<h1>Title</h1>}><p>Body</p></Panel>")
    assert_equal "<div><header><h1>Title</h1></header><p>Body</p></div>", html
  end

  def test_namespaced_components
    define(<<~RSX, name: "Admin::Button")
      component Admin::Button do |label:|
        return <button className="admin">{label}</button>
      end
    RSX

    assert_equal %(<button class="admin">Go</button>), render(%(<Admin::Button label="Go" />))
  end

  def test_lambda_function_components
    Object.const_set(:Tiny, ->(props) { RSX.render_source("<em>{props[:text]}</em>", text: props[:text]) })

    assert_equal "<em>hi</em>", render(%(<Tiny text="hi" />))
  ensure
    Object.send(:remove_const, :Tiny) if Object.const_defined?(:Tiny, false)
  end

  def test_components_compose_recursively
    define(<<~RSX, name: "Tree")
      component Tree do |node:|
        return (
          <li>
            {node[:name]}
            {node[:children] && (
              <ul>
                {node[:children].map { |kid| <Tree node={kid} /> }}
              </ul>
            )}
          </li>
        )
      end
    RSX

    tree = { name: "a", children: [{ name: "b" }, { name: "c", children: [{ name: "d" }] }] }
    html = render("<ul><Tree node={props[:tree]} /></ul>", tree: tree)
    assert_equal "<ul><li>a<ul><li>b</li><li>c<ul><li>d</li></ul></li></ul></li></ul>", html
  end

  def test_component_rendered_through_public_api
    component = define(<<~RSX, name: "Api")
      component Api do |value:|
        return <p>{value}</p>
      end
    RSX

    assert_equal "<p>7</p>", RSX.render(component, value: 7).to_s
    assert_kind_of RSX::SafeString, RSX.render(component, value: 7)
  end

  def test_unknown_component_tag_raises
    error = assert_raises(NameError) { render("<Nope />") }
    assert_match(/Nope/, error.message)
  end

  def test_rendering_a_component_class_as_a_value_is_rejected
    component = define(<<~RSX, name: "AsValue")
      component AsValue do |props|
        return <p>x</p>
      end
    RSX

    error = assert_raises(RSX::Error) { render("<div>{AsValue}</div>") }
    assert_match(/Write <AsValue \/>/, error.message)
    assert component
  end
end

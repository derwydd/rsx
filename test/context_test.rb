# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test
  include RSXTest

  def setup
    super
    Object.const_set(:Theme, RSX.create_context("light", name: "Theme"))
  end

  def teardown
    Object.send(:remove_const, :Theme) if Object.const_defined?(:Theme, false)
    super
  end

  def test_default_value_is_used_without_a_provider
    define(<<~RSX, name: "Themed")
      component Themed do |props|
        return <p>{use_context(Theme)}</p>
      end
    RSX

    assert_equal "<p>light</p>", render("<Themed />")
  end

  def test_provider_supplies_the_value_to_descendants
    define(<<~RSX, name: "Themed")
      component Themed do |props|
        return <p>{use_context(Theme)}</p>
      end
    RSX

    html = render(%(<Theme.Provider value={"dark"}><Themed /></Theme.Provider>))
    assert_equal "<p>dark</p>", html
  end

  def test_providers_nest
    define(<<~RSX, name: "Themed")
      component Themed do |props|
        return <p>{use_context(Theme)}</p>
      end
    RSX

    source = <<~RSX
      <Theme.Provider value={"dark"}>
        <Themed />
        <Theme.Provider value={"sepia"}>
          <Themed />
        </Theme.Provider>
        <Themed />
      </Theme.Provider>
    RSX

    assert_equal "<p>dark</p><p>sepia</p><p>dark</p>", render(source)
  end

  def test_value_is_restored_after_the_provider_closes
    define(<<~RSX, name: "Themed")
      component Themed do |props|
        return <p>{use_context(Theme)}</p>
      end
    RSX

    source = <<~RSX
      <>
        <Theme.Provider value={"dark"}><Themed /></Theme.Provider>
        <Themed />
      </>
    RSX

    assert_equal "<p>dark</p><p>light</p>", render(source)
    assert_equal "light", Theme.value
  end

  def test_context_is_readable_outside_a_component
    assert_equal "light", Theme.value
    Theme.with("dark") { assert_equal "dark", Theme.value }
    assert_equal "light", Theme.value
  end

  def test_render_props_receive_a_value
    define(<<~RSX, name: "Consumer")
      component Consumer do |children: nil|
        return <div>{children.call(use_context(Theme))}</div>
      end
    RSX

    html = render(%(<Consumer>{->(theme) { <b>{theme}</b> }}</Consumer>))
    assert_equal "<div><b>light</b></div>", html
  end
end

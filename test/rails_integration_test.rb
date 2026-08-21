# frozen_string_literal: true

require "test_helper"

begin
  require "action_view"
  require "action_view/base"
rescue LoadError
  ACTION_VIEW_AVAILABLE = false
else
  ACTION_VIEW_AVAILABLE = true
  require "rsx/template_handler"
  require "rsx/helpers"
end

class RailsIntegrationTest < Minitest::Test
  include RSXTest

  VIEWS = File.expand_path("fixtures/views", __dir__)

  def setup
    skip "action_view is not installed" unless ACTION_VIEW_AVAILABLE

    super
    ActionView::Template.register_template_handler(:rsx, RSX::TemplateHandler)
    ActionView::Base.include(RSX::Helpers)
  end

  def view(assigns = {})
    lookup = ActionView::LookupContext.new([ActionView::FileSystemResolver.new(VIEWS)])
    base = ActionView::Base.with_empty_template_cache.new(lookup, assigns, nil)
    base.assign(assigns)
    base
  end

  def test_renders_an_rsx_template
    html = view(title: "Post", intro: "Lead").render(template: "demo/show")

    assert_includes html, %(<article class="post">)
    assert_includes html, "<h1>Post</h1>"
    assert_includes html, %(<p class="intro">Lead</p>)
  end

  def test_partials_and_locals
    html = view(title: "t", intro: "i").render(template: "demo/show")

    assert_includes html, %(<div class="row" data-name="Ada">Ada</div>)
  end

  def test_rails_helpers_are_available
    html = view(title: "t", intro: "i").render(template: "demo/show")

    assert_includes html, %(<footer><a href="/">Home</a></footer>)
  end

  def test_output_is_html_safe_and_values_are_escaped
    html = view(title: "<script>", intro: "&").render(template: "demo/show")

    assert_predicate html, :html_safe?
    assert_includes html, "<h1>&lt;script&gt;</h1>"
    assert_includes html, %(<p class="intro">&amp;</p>)
  end

  def test_rsx_helper_renders_a_component_from_erb
    define(<<~RSX, name: "HelperCard")
      component HelperCard do |title:, children: nil|
        return <section><h2>{title}</h2>{children}</section>
      end
    RSX

    html = view.render(inline: <<~ERB, type: :erb)
      <%= rsx HelperCard, title: "From ERB" do %>
        <p>Block body</p>
      <% end %>
    ERB

    assert_includes html, "<section><h2>From ERB</h2>"
    assert_includes html, "<p>Block body</p>"
  end

  def test_rsx_helper_accepts_a_component_name
    define(<<~RSX, name: "NamedCard")
      component NamedCard do |props|
        return <p>named</p>
      end
    RSX

    html = view.render(inline: %(<%= rsx "NamedCard" %>), type: :erb)
    assert_includes html, "<p>named</p>"
  end

  def test_components_can_use_rails_helpers_through_the_view_context
    define(<<~RSX, name: "Linked")
      component Linked do |props|
        return <p>{helpers.link_to("Docs", "/docs")}</p>
      end
    RSX

    html = view.render(inline: %(<%= rsx Linked %>), type: :erb)
    assert_includes html, %(<p><a href="/docs">Docs</a></p>)
  end

  def test_active_support_safe_buffers_are_not_double_escaped
    buffer = ActiveSupport::SafeBuffer.new("<b>safe</b>")
    assert_equal "<p><b>safe</b></p>", render("<p>{props[:value]}</p>", value: buffer)
  end

  def test_unsafe_strings_from_rails_are_escaped
    assert_equal "<p>&lt;b&gt;</p>", render("<p>{props[:value]}</p>", value: "<b>")
  end
end

# frozen_string_literal: true

require "test_helper"

begin
  require "action_view"
  require "action_view/base"
rescue LoadError
  EXAMPLES_ACTION_VIEW = false
else
  EXAMPLES_ACTION_VIEW = true
  require "rsx/template_handler"
  require "rsx/helpers"
end

# The examples double as documentation, so they are compiled and rendered here
# to keep them honest.
class ExamplesTest < Minitest::Test
  include RSXTest

  EXAMPLES = File.expand_path("../examples", __dir__)

  def setup
    super
    RSX.config.paths = [EXAMPLES]
  end

  def teardown
    %w[UserProfile Button Card UserTable Sidebar Theme ThemedPanel ThemeDemo].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
    super
  end

  def test_every_example_compiles
    files = Dir.glob(File.join(EXAMPLES, "**", "*.rsx"))
    refute_empty files

    files.each do |file|
      RSX.compile(File.read(file), path: file)
    rescue RSX::SyntaxError => e
      flunk "#{file} failed to compile: #{e.message}"
    end
  end

  def test_user_profile
    html = RSX.render_file(File.join(EXAMPLES, "user_profile.rsx")).to_s

    assert_includes html, "<h1>Welcome back, Jane Doe!</h1>"
    assert_includes html, %(class="profile-image")
    assert_includes html, %(<p style="color:darkred;background-color:pink;padding:10px;border-radius:5px">)
    assert_includes html, %(<button onclick="alert(&#39;Settings opened!&#39;)">)
  end

  def test_button
    RSX.load(File.join(EXAMPLES, "components/button.rsx"))

    assert_equal %(<button class="btn btn-primary btn-md">Save</button>),
                 Button.call(label: "Save").to_s

    assert_equal %(<button class="btn btn-danger btn-sm" disabled aria-disabled="true" id="x">Go</button>),
                 Button.call(label: "Go", variant: "danger", size: "sm", disabled: true, id: "x").to_s
  end

  def test_card_with_children_and_slots
    RSX.load(File.join(EXAMPLES, "components/card.rsx"))

    html = RSX.render_source(<<~RSX).to_s
      <Card title="Hello" footer={<a href="/more">More</a>}>
        <p>Body</p>
      </Card>
    RSX

    assert_includes html, %(<h2 class="card-title">Hello</h2>)
    assert_includes html, %(<div class="card-body"><p>Body</p></div>)
    assert_includes html, %(<footer class="card-footer"><a href="/more">More</a></footer>)
  end

  def test_user_table
    RSX.load(File.join(EXAMPLES, "components/user_table.rsx"))

    ada = { id: 1, name: "Ada Lovelace", active: true, posts_count: 12 }
    alan = { id: 2, name: "Alan Turing", active: false, posts_count: 3 }
    html = UserTable.call(users: [ada, alan], current_user: ada).to_s

    assert_includes html, %(<span class="avatar">AL</span>)
    assert_includes html, %(<em class="you"> (you)</em>)
    assert_includes html, %(<td style="color:#0a7;font-weight:600">Active</td>)
    assert_includes html, %(<td style="color:#999;font-weight:400">Inactive</td>)
    assert_includes html, %(data-user-id="2")
    assert_operator html.index("Ada Lovelace"), :<, html.index("Alan")
    refute_includes html, "Nobody here yet"
  end

  def test_user_table_empty_state
    RSX.load(File.join(EXAMPLES, "components/user_table.rsx"))

    html = UserTable.call(users: []).to_s
    assert_includes html, %(<td colspan="4">Nobody here yet.</td>)
  end

  def test_sidebar_caches_its_output
    RSX.load(File.join(EXAMPLES, "components/sidebar.rsx"))

    props = { section: "projects", unread: 4 }
    html = Sidebar.call(**props).to_s

    assert_includes html, %(<li class="current"><a href="/projects">Projects</a></li>)
    assert_includes html, %(<p class="unread">4 unread</p>)

    key = Sidebar.rsx_cache_key(props, Sidebar.rsx_cache_options)
    assert_equal html, RSX.cache.read(key).to_s
    assert_equal html, Sidebar.call(**props).to_s
  end

  def test_theme_context
    RSX.load(File.join(EXAMPLES, "components/theme.rsx"))

    html = ThemeDemo.call.to_s
    assert_includes html, %(<div class="panel panel-light" data-theme="light">)
    assert_includes html, %(<div class="panel panel-dark" data-theme="dark">)
  end

  def test_dashboard_view
    skip "action_view is not installed" unless EXAMPLES_ACTION_VIEW

    ActionView::Template.register_template_handler(:rsx, RSX::TemplateHandler)
    ActionView::Base.include(RSX::Helpers)

    assigns = { users: [{ id: 1, name: "Ada Lovelace", active: true, posts_count: 2 }],
                current_user: nil, unread_count: 3 }
    lookup = ActionView::LookupContext.new([ActionView::FileSystemResolver.new(EXAMPLES)])
    view = ActionView::Base.with_empty_template_cache.new(lookup, assigns, nil)
    view.assign(assigns)

    html = view.render(template: "views/dashboard")

    assert_includes html, %(<nav class="sidebar")
    assert_includes html, %(<p class="unread">3 unread</p>)
    assert_includes html, "Ada Lovelace"
    assert_includes html, "Invite someone"
    refute_includes html, "Getting started"
  end
end

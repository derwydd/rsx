# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class LoaderTest < Minitest::Test
  include RSXTest

  FIXTURES = File.expand_path("fixtures", __dir__)

  def teardown
    %i[FixtureButton FixturePage Alpha Beta Renamed].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
    super
  end

  def test_loading_a_file_defines_its_components
    RSX.load(File.join(FIXTURES, "fixture_button.rsx"))

    assert Object.const_defined?(:FixtureButton)
    assert_equal %(<button class="btn btn-primary">Go</button>),
                 FixtureButton.call(label: "Go").to_s
  end

  def test_default_export_is_recorded
    entry = RSX.load(File.join(FIXTURES, "fixture_button.rsx"))
    assert_equal FixtureButton, entry.default
  end

  def test_import_loads_a_dependency
    html = RSX.render_file(File.join(FIXTURES, "fixture_page.rsx"), title: "Dashboard")

    assert_equal %(<main class="page"><h1>Dashboard</h1>) +
                 %(<button class="btn btn-danger">Go</button></main>),
                 html.to_s
  end

  def test_render_file_renders_a_template_without_components
    html = RSX.render_file(File.join(FIXTURES, "greeting.html.rsx"), name: "Ada")

    assert_equal %(<section class="greeting"><h1>Hello, Ada!</h1></section>), html.to_s
  end

  def test_resolve_adds_the_extension
    resolved = RSX.loader.resolve("fixture_button")
    assert_equal File.join(FIXTURES, "fixture_button.rsx"), resolved
  end

  def test_resolve_finds_html_rsx
    resolved = RSX.loader.resolve("greeting")
    assert_equal File.join(FIXTURES, "greeting.html.rsx"), resolved
  end

  def test_missing_file_raises_with_the_search_path
    error = assert_raises(RSX::FileNotFoundError) { RSX.render_file("nope") }
    assert_match(/could not find `nope`/, error.message)
    assert_match(/fixtures/, error.message)
  end

  def test_lookup_by_component_name_loads_the_file
    component = RSX.lookup_component("fixture_button")
    assert_equal FixtureButton, component
  end

  def test_files_lists_every_rsx_file
    files = RSX.loader.files([FIXTURES])
    assert_includes files, File.join(FIXTURES, "fixture_button.rsx")
    assert_includes files, File.join(FIXTURES, "greeting.html.rsx")
  end

  def test_reload_picks_up_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "alpha.rsx")
      File.write(path, "component Alpha do |props|\n  return <p>one</p>\nend\n")

      RSX.config.paths = [dir]
      RSX.load(path)
      assert_equal "<p>one</p>", Alpha.call.to_s

      File.write(path, "component Alpha do |props|\n  return <p>two</p>\nend\n")
      File.utime(Time.now + 2, Time.now + 2, path)
      RSX.reload!

      assert_equal "<p>two</p>", Alpha.call.to_s
    end
  end

  def test_reload_removes_components_from_deleted_files
    Dir.mktmpdir do |dir|
      path = File.join(dir, "beta.rsx")
      File.write(path, "component Beta do |props|\n  return <p>b</p>\nend\n")

      RSX.config.paths = [dir]
      RSX.load(path)
      assert Object.const_defined?(:Beta)

      File.delete(path)
      RSX.reload!

      refute Object.const_defined?(:Beta, false)
    end
  end

  def test_loading_twice_does_not_recompile
    path = File.join(FIXTURES, "fixture_button.rsx")
    first = RSX.load(path)
    second = RSX.load(path)

    assert_same first, second
  end

  def test_import_can_rename_a_component
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "widget.rsx"), <<~RSX)
        component Alpha do |props|
          return <p>alpha</p>
        end

        export default Alpha
      RSX
      File.write(File.join(dir, "user.rsx"), <<~RSX)
        import Renamed from "widget"

        component Beta do |props|
          return <div><Renamed /></div>
        end

        export default Beta
      RSX

      RSX.config.paths = [dir]
      html = RSX.render_file(File.join(dir, "user.rsx"))
      assert_equal "<div><p>alpha</p></div>", html.to_s
      assert_equal Alpha, Renamed
    end
  end

  # Every edit compiles the file under a fresh set of static slots, so the ones
  # belonging to the version being replaced have to go with it.
  def test_reloading_discards_the_previous_versions_static_slots
    Dir.mktmpdir do |dir|
      path = File.join(dir, "alpha.rsx")
      RSX.config.paths = [dir]

      3.times do |version|
        File.write(path, "component Alpha do |props|\n  return <p>v#{version}</p>\nend\n")
        File.utime(Time.now + version, Time.now + version, path)
        RSX.reload!
        RSX.load(path)
        Alpha.call.to_s
      end

      assert_equal 1, RSX::STATICS.length
    end
  end

  # Loading a template evaluates it, so a spec that came from a request must not
  # be able to name a file outside the configured paths.
  def test_resolution_stays_inside_the_configured_paths
    assert_nil RSX.loader.resolve("../../../../etc/passwd")
    assert_nil RSX.loader.resolve("/etc/passwd")
  end

  def test_a_file_outside_the_configured_paths_says_so
    Dir.mktmpdir do |dir|
      outside = File.join(dir, "outside.rsx")
      File.write(outside, "<p>x</p>\n")

      error = assert_raises(RSX::FileNotFoundError) { RSX.render_file(outside) }
      assert_includes error.message, "outside the configured RSX paths"
    end
  end

  def test_only_rsx_files_are_resolved
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "secrets.yml"), "password: hunter2\n")
      RSX.config.paths = [dir]

      assert_nil RSX.loader.resolve("secrets.yml")
    end
  end

  def test_adding_the_directory_makes_it_resolvable
    Dir.mktmpdir do |dir|
      path = File.join(dir, "inside.rsx")
      File.write(path, "<p>x</p>\n")
      RSX.config.paths = [dir]

      assert_equal "<p>x</p>", RSX.render_file(path).to_s
    end
  end

  def test_syntax_errors_name_the_file_and_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.rsx")
      File.write(path, "<div>\n  <p>oops</div>\n")

      error = assert_raises(RSX::SyntaxError) { RSX.load(path) }
      assert_match(/broken\.rsx/, error.message)
    end
  end
end

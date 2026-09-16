# frozen_string_literal: true

require "test_helper"

begin
  require "rails/generators"
  require "rails/generators/test_case"
  require "generators/rsx/component/component_generator"
rescue LoadError
  RAILS_GENERATORS_AVAILABLE = false
else
  RAILS_GENERATORS_AVAILABLE = true
end

# rails generate rsx:component
class ComponentGeneratorTest < defined?(Rails::Generators::TestCase) ? Rails::Generators::TestCase : Minitest::Test
  include RSXTest

  if RAILS_GENERATORS_AVAILABLE
    tests RSX::Generators::ComponentGenerator
    destination File.expand_path("../tmp/generator", __dir__)
    setup :prepare_destination
  end

  def setup
    require_rails!(RAILS_GENERATORS_AVAILABLE, "rails generators")

    super
    RSX.config.paths = []
  end

  # `rails g rsx:component` has to resolve to this generator by namespace, which
  # is derived from the class name rather than declared.
  def test_the_generator_is_registered_under_rsx_component
    assert_equal "rsx:component", RSX::Generators::ComponentGenerator.namespace
    assert_equal RSX::Generators::ComponentGenerator,
                 Rails::Generators.find_by_namespace("component", "rsx")
  end

  def test_generates_a_component_with_keyword_props
    run_generator %w[Card title body]

    assert_file "app/components/card.rsx" do |content|
      assert_match(/\Acomponent Card do \|title:, body:\|$/, content)
      assert_match(%r{<p className="card__title">\{title\}</p>}, content)
      assert_match(/export default Card\n\z/, content)
    end
  end

  def test_generates_a_component_without_props
    run_generator %w[Spinner]

    assert_file "app/components/spinner.rsx" do |content|
      assert_match(/component Spinner do \|props\|/, content)
    end
  end

  def test_generates_a_namespaced_component
    run_generator %w[Admin::Card]

    assert_file "app/components/admin/card.rsx" do |content|
      assert_match(/component Admin::Card do/, content)
      assert_match(/export default Admin::Card/, content)
    end
  end

  # The generated file has to be valid .rsx, or the generator is worse than
  # writing the file by hand.
  def test_the_generated_component_compiles_and_renders
    run_generator %w[Card title body]

    source = File.read(File.join(destination_root, "app/components/card.rsx"))
    RSX.config.cache_dir = nil
    RSX::Template.new(source).component.new.rsx_render(nil)

    begin
      html = Object.const_get(:Card).call(title: "T", body: "B").to_s
      assert_equal %(<div class="card"><p class="card__title">T</p>) +
                   %(<p class="card__body">B</p></div>), html
    ensure
      Object.send(:remove_const, :Card) if Object.const_defined?(:Card, false)
    end
  end

  # The component belongs wherever the loader is already looking.
  def test_writes_into_the_first_configured_rsx_path
    RSX.config.paths = [File.join(destination_root, "app/views/rsx")]
    run_generator %w[Card]

    assert_file "app/views/rsx/card.rsx"
  end
end

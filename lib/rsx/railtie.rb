# frozen_string_literal: true

require_relative "template_handler"
require_relative "helpers"

module RSX
  # Wires RSX into a Rails application. Nothing here runs unless Rails is
  # already loaded, which keeps the gem usable outside Rails.
  #
  # Configure it from config/application.rb:
  #
  #   config.rsx.paths = [Rails.root.join("app/components")]
  #   config.rsx.cache_store = :rails
  #
  class Railtie < ::Rails::Railtie
    config.rsx = ActiveSupport::OrderedOptions.new

    initializer "rsx.configure" do |app|
      options = app.config.rsx

      RSX.configure do |config|
        config.paths = Array(options.paths.presence || default_paths(app))
        config.cache_dir = options.key?(:cache_dir) ? options.cache_dir : app.root.join("tmp/cache/rsx").to_s
        config.component_namespace = options.component_namespace || Object
        config.reload = options.key?(:reload) ? options.reload : reloading?(app)
        config.cache_store = build_cache_store(options.cache_store) if options.cache_store
      end
    end

    initializer "rsx.action_view" do
      ActiveSupport.on_load(:action_view) do
        ActionView::Template.register_template_handler(:rsx, RSX::TemplateHandler)
        RSX::TemplateHandler.register_dependency_tracker
        include RSX::Helpers
      end
    end

    initializer "rsx.load_components" do |app|
      # Eager load in production so no request ever pays for compilation, and
      # reload changed files between requests in development.
      if app.config.eager_load
        app.config.after_initialize { RSX.load_all }
      else
        app.reloader.to_prepare { RSX.reload! if RSX.config.reload }
      end

      app.config.watchable_dirs ||= {}
      Array(RSX.config.paths).each do |path|
        app.config.watchable_dirs[path.to_s] = [:rsx] if File.directory?(path.to_s)
      end
    end

    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end

    # Initializer blocks are instance_exec'd on the railtie instance, so these
    # helpers have to be instance methods.
    private

    def default_paths(app)
      %w[app/components app/rsx].map { |path| app.root.join(path).to_s }
    end

    def reloading?(app)
      if app.config.respond_to?(:enable_reloading)
        app.config.enable_reloading
      else
        !app.config.cache_classes
      end
    end

    def build_cache_store(setting)
      case setting
      when :rails, "rails" then Cache::Rails.new
      when :memory, "memory" then Cache::Memory.new
      when :null, "null", false then Cache::Null.new
      else setting
      end
    end
  end
end

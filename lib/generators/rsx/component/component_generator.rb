# frozen_string_literal: true

require "pathname"
require "rails/generators/named_base"

module RSX
  module Generators
    # rails generate rsx:component Card title body
    #
    # Writes the component into the first configured RSX path, so the file lands
    # somewhere the loader already looks.
    class ComponentGenerator < ::Rails::Generators::NamedBase
      # Thor derives a namespace by inserting an underscore before every capital,
      # which turns RSX into "r_s_x". Declare the real one.
      namespace "rsx:component"

      source_root File.expand_path("templates", __dir__)

      desc "Creates an RSX component with one keyword prop per given name."

      argument :props, type: :array, default: [], banner: "prop prop"

      def create_component_file
        template "component.rsx.tt", File.join(component_root, "#{file_path}.rsx")
      end

      private

      DEFAULT_ROOT = "app/components"

      def component_root
        configured = Array(::RSX.config.paths).first
        return DEFAULT_ROOT if configured.nil?

        relative = Pathname.new(configured.to_s).relative_path_from(Pathname.new(destination_root)).to_s
        relative.start_with?("..") ? DEFAULT_ROOT : relative
      rescue ArgumentError
        # The configured path is on another volume, so it cannot be expressed
        # relative to the application root.
        DEFAULT_ROOT
      end

      def parameter_list
        return "props" if props.empty?

        props.map { |prop| "#{prop}:" }.join(", ")
      end
    end
  end
end

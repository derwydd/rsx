# frozen_string_literal: true

module RSX
  # Mixed into ActionView so components can be rendered from ERB, Haml, Slim or
  # anywhere else a view helper is available.
  #
  #   <%= rsx UserProfile, user: @user %>
  #   <%= rsx "Card", title: "Hello" do %>
  #     <p>Body rendered by ERB, passed to the component as children.</p>
  #   <% end %>
  module Helpers
    def rsx(target, **props, &block)
      children =
        if block
          captured = capture(&block)
          RSX::Children.new { RSX.raw(captured) }
        end

      component = target.is_a?(String) || target.is_a?(Symbol) ? RSX.lookup_component(target) : target
      RSX.safe(RSX.render_component(component, props.empty? ? nil : props, children, self))
    end
    alias render_rsx rsx

    # Renders a .rsx file directly by path, relative to the configured paths.
    def rsx_file(path, **props)
      RSX.render_file(path, context: self, **props)
    end
  end
end

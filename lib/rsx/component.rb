# frozen_string_literal: true

module RSX
  # Base class for every `component` defined in a .rsx file.
  #
  #   component Greeting do |name:|
  #     return <p>Hello {name}</p>
  #   end
  #
  # compiles to a subclass whose `rsx_render` is the block body. Components are
  # plain Ruby objects: one instance per render, no inheritance requirements on
  # the caller, and no framework needed to use them.
  class Component
    EMPTY_PROPS = {}.freeze

    class << self
      attr_accessor :rsx_source_path, :rsx_source_digest, :rsx_cache_options

      # Marks a component whose output never varies. The compiler sets this
      # automatically when a component body is nothing but static markup.
      def rsx_static!
        @rsx_static = true
      end

      def rsx_static?
        @rsx_static ? true : false
      end

      # Enables whole-component caching.
      #
      #   cache expires_in: 300
      #   cache key: ->(props) { [props[:user], props[:locale]] }
      def cache(options = true)
        @rsx_cache_options = RSX.normalize_cache_options(options)
      end

      # Renders the component. This is the entry point used by compiled markup.
      def rsx_call(props = nil, parent = nil)
        return (@rsx_static_output ||= new(props, parent).rsx_perform) if rsx_static?

        options = rsx_cache_options
        return new(props, parent).rsx_perform unless options

        key = rsx_cache_key(props, options)
        cached = RSX.cache.fetch(key, expires_in: options[:expires_in]) do
          new(props, parent).rsx_perform.to_s
        end
        cached.is_a?(SafeString) ? cached : SafeString.new(cached)
      end

      # Public API: Button.call(label: "Save") => SafeString
      def call(**props)
        rsx_call(props)
      end

      def render(**props)
        rsx_call(props)
      end

      def rsx_cache_key(props, options)
        custom = options[:key]
        payload =
          if custom.nil?
            (props || EMPTY_PROPS).except(:children)
          elsif custom.respond_to?(:arity) && custom.arity.zero?
            custom.call
          else
            custom.call(props || EMPTY_PROPS)
          end

        "rsx/#{name || "component"}/#{rsx_source_digest || "0"}/#{RSX.stable_key(payload)}"
      end

      def rsx_render_style
        return @rsx_render_style if defined?(@rsx_render_style)

        parameters = rsx_render_parameters
        keyword = parameters.any? { |kind, _| %i[key keyreq keyrest].include?(kind) }
        @rsx_render_style = keyword ? :keyword : :positional
      end

      def rsx_render_parameters
        instance_method(:rsx_render).parameters
      rescue NameError
        []
      end

      # The keyword props this component declares.
      def rsx_accepted_props
        @rsx_accepted_props ||= rsx_render_parameters.filter_map do |kind, name|
          name if %i[key keyreq].include?(kind)
        end
      end

      def rsx_accepts_extra_props?
        return @rsx_accepts_extra_props if defined?(@rsx_accepts_extra_props)

        @rsx_accepts_extra_props = rsx_render_parameters.any? { |kind, _| kind == :keyrest }
      end

      def rsx_filter_props(props)
        return EMPTY_PROPS if props.nil? || props.empty?
        return props if rsx_accepts_extra_props?

        accepted = rsx_accepted_props
        unknown = props.keys - accepted - [:children]
        unless unknown.empty?
          raise PropsError, "#{name} does not accept #{unknown.map(&:inspect).join(", ")}. " \
                            "Declared props: #{accepted.map(&:inspect).join(", ")}. " \
                            "Add `**rest` to the component parameters to accept anything else."
        end

        accepted.include?(:children) ? props : props.except(:children)
      end

      def inspect
        name || super
      end
    end

    attr_reader :props

    def initialize(props = nil, parent = nil)
      @props = props || EMPTY_PROPS
      @rsx_parent = parent
    end

    def rsx_perform
      result =
        if self.class.rsx_render_style == :keyword
          rsx_render(**self.class.rsx_filter_props(@props))
        else
          rsx_render(@props)
        end
      RSX.child(result)
    rescue ArgumentError => e
      raise unless e.message.start_with?("missing keyword", "unknown keyword", "wrong number of arguments")

      raise PropsError, "#{self.class.name}: #{e.message}. " \
                        "Declared props: #{self.class.rsx_accepted_props.map(&:inspect).join(", ")}"
    end

    # The markup nested inside this component's tag, rendered on demand.
    def children
      @props[:children]
    end

    def children?
      child = children
      !child.nil? && !(child.respond_to?(:empty?) && child.empty?)
    end

    # The object that rendered this component: a view context in Rails, the
    # parent component when nested, or nil when rendered directly.
    attr_reader :rsx_parent

    # The nearest non-component render context, i.e. the Rails view. Gives access
    # to url helpers, form builders, `t`, asset helpers and anything else the
    # application exposes to templates.
    def helpers
      node = @rsx_parent
      node = node.rsx_parent while node.is_a?(Component)
      return node unless node.nil?

      raise Error, "#{self.class.name} has no view context. Render it from a Rails view, " \
                   "or pass one with RSX.render(#{self.class.name}, context: view)."
    end
    alias view_context helpers

    def helpers?
      node = @rsx_parent
      node = node.rsx_parent while node.is_a?(Component)
      !node.nil?
    end

    # Reads a value provided by an enclosing <Ctx.Provider>.
    def use_context(context)
      context.value
    end

    # Caches a fragment of markup.
    #
    #   {cache(["sidebar", user.id], expires_in: 300) do
    #     <nav>...</nav>
    #   end}
    def cache(key, expires_in: nil)
      full_key = "rsx/#{self.class.name}/#{self.class.rsx_source_digest || "0"}/#{RSX.stable_key(key)}"
      cached = RSX.cache.fetch(full_key, expires_in: expires_in) { RSX.child(yield).to_s }
      cached.is_a?(SafeString) ? cached : SafeString.new(cached)
    end

    # Escape hatch for trusted HTML built elsewhere.
    def raw(value)
      RSX.raw(value)
    end

    def to_s
      rsx_perform
    end

    def inspect
      "#<#{self.class.name} #{@props.inspect}>"
    end
  end
end

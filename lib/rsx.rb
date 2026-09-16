# frozen_string_literal: true

require "digest"

require_relative "rsx/version"
require_relative "rsx/errors"
require_relative "rsx/safe_string"
require_relative "rsx/escape"
require_relative "rsx/attributes"
require_relative "rsx/children"
require_relative "rsx/nodes"
require_relative "rsx/codegen"
require_relative "rsx/transformer"
require_relative "rsx/cache"
require_relative "rsx/compile_cache"
require_relative "rsx/component"
require_relative "rsx/context"
require_relative "rsx/loader"
require_relative "rsx/template"

# RSX brings JSX authoring to Ruby.
#
#   component Greeting do |name:|
#     return <p className="greeting">Hello, {name}!</p>
#   end
#
# Markup is compiled ahead of time into Ruby string building, so rendering is
# just concatenation and escaping. See README.md for the full language guide.
module RSX
  EMPTY_SAFE = SafeString.new("").freeze

  # Slots for markup that never changes, populated on first render by compiled
  # templates. Keys are generated at compile time, one per call site.
  #
  # Compiled markup reads a slot directly and only calls define_static on a miss,
  # so the render path is a bare Hash read and the lock is paid once per slot.
  STATICS = {}
  STATICS_LOCK = Mutex.new

  # Configuration is intentionally small: where to find components, where to put
  # compiled output, and which cache to use.
  class Configuration
    # Directories searched for .rsx files and imports.
    attr_accessor :paths

    # Where compiled Ruby is cached. Set to nil to compile in memory only.
    attr_reader :cache_dir

    # Any object responding to fetch(key, expires_in:) { } and clear.
    attr_writer :cache_store

    # Namespace that `component Name` constants are defined under.
    attr_accessor :component_namespace

    # Reload changed .rsx files automatically (development).
    attr_accessor :reload

    def initialize
      @paths = []
      @component_namespace = Object
      @reload = false
      self.cache_dir = default_cache_dir
    end

    def cache_dir=(directory)
      @cache_dir = directory
      @compile_cache = CompileCache.new(directory)
    end

    def compile_cache
      @compile_cache ||= CompileCache.new(@cache_dir)
    end

    def cache_store
      @cache_store ||= Cache::Memory.new
    end

    private

    def default_cache_dir
      if defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root
        ::Rails.root.join("tmp/cache/rsx").to_s
      else
        File.join(Dir.pwd, "tmp", "cache", "rsx")
      end
    end
  end

  class << self
    # ------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------

    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    def loader
      @loader ||= Loader.new(config)
    end

    def cache
      config.cache_store
    end

    def reset!
      @config = nil
      @loader = nil
      @templates = nil
      STATICS.clear
    end

    # ------------------------------------------------------------------
    # Compiling and loading
    # ------------------------------------------------------------------

    # Transforms .rsx source into plain Ruby. Useful for debugging: `rsx compile`.
    def compile(source, path: nil)
      Transformer.transform(source, path: path)
    end

    def load(path)
      loader.load(path)
    end

    def load_all(paths = config.paths)
      loader.load_all(paths)
    end

    def reload!
      loader.reload!
    end

    # Compiles every .rsx file under the configured paths and warms the on-disk
    # cache. Run at boot (or from `rake rsx:precompile`) so requests never
    # compile anything.
    def precompile!(paths = config.paths)
      loader.files(paths).each do |file|
        source = File.read(file)
        config.compile_cache.fetch(file, source) { Transformer.transform(source, path: file) }
      end
    end

    # The compiled Template for a markup .rsx file.
    def template(path)
      entry = loader.load(loader.resolve!(path))
      entry.template || raise(Error, "#{entry.path} defines components; render one of them instead")
    end

    # ------------------------------------------------------------------
    # Rendering
    # ------------------------------------------------------------------

    # Renders a component, a .rsx file path, or a lambda component.
    #
    #   RSX.render(UserProfile, user: user)
    #   RSX.render("app/components/user_profile.rsx", user: user)
    def render(target, context: nil, **props)
      if target.is_a?(String) || target.respond_to?(:to_path)
        render_file(target.to_s, context: context, **props)
      else
        safe(render_component(target, props.empty? ? nil : props, nil, context))
      end
    end

    def render_file(path, context: nil, **props)
      entry = loader.load(loader.resolve!(path))
      props = props.empty? ? nil : props
      component = entry.renderable

      if component
        safe(render_component(component, props, nil, context))
      else
        entry.template.render(props, context: context)
      end
    end

    # Renders .rsx source directly. Handy in tests and scripts.
    def render_source(source, path: nil, context: nil, **props)
      Template.new(source, path: path).render(props.empty? ? nil : props, context: context)
    end

    # Internal: wraps the value of a compiled ActionView template.
    def template_result(value)
      safe(child(value))
    end

    # Internal: emitted by compiled markup for every <Component /> tag.
    def render_component(target, props = nil, children = nil, parent = nil)
      # Copied rather than written into, so that a caller holding the hash does
      # not find :children added to it.
      props = props ? props.merge(children: children) : { children: children } if children

      case target
      when Proc
        child(target.arity.zero? ? target.call : target.call(props || Component::EMPTY_PROPS))
      when String, Symbol
        render_component(lookup_component(target), props, nil, parent)
      else
        unless target.respond_to?(:rsx_call)
          raise UnknownComponentError,
                "#{target.inspect} is not renderable. Components are defined with " \
                "`component Name do ... end` in a .rsx file."
        end

        target.rsx_call(props, parent)
      end
    end

    def lookup_component(name)
      name = name.to_s
      namespace = config.component_namespace
      return namespace.const_get(name) if constant_defined?(name)

      resolved = loader.resolve(name)
      return loader.default_export(resolved) if resolved

      raise UnknownComponentError, "no component named #{name}"
    end

    # ------------------------------------------------------------------
    # Runtime emitted by compiled markup
    # ------------------------------------------------------------------

    # Coerces any value into markup, escaping it unless it is already safe.
    # Mirrors React: nil, true and false render nothing, arrays are concatenated.
    def child(value)
      case value
      when SafeString then value
      when String then Escape.safe?(value) ? value : Escape.html(value)
      when nil, true, false then EMPTY_SAFE
      when Children then value.render
      when Integer, Float, Symbol then value.to_s
      when Array
        out = +""
        value.each { |item| out << child(item) }
        out
      when Component then value.rsx_perform
      when Hash
        raise Error, "cannot render a Hash. Did you mean to interpolate one of its values?"
      else
        if value.respond_to?(:html_safe?) && value.html_safe?
          value.to_s
        elsif value.respond_to?(:to_rsx)
          child(value.to_rsx)
        elsif value.is_a?(Class) && value < Component
          raise Error, "cannot render the component class #{value.name} as a value. " \
                       "Write <#{value.name} /> to render it."
        else
          Escape.html(value.to_s)
        end
      end
    end

    # Internal: fills a static slot the first time its call site renders.
    def define_static(key, literal)
      STATICS_LOCK.synchronize { STATICS[key] ||= SafeString.new(literal).freeze }
    end

    # Internal: drops the slots belonging to one compiled version of a file.
    # Editing a file in development compiles it under a fresh set of keys, and the
    # old ones can never be reached again, so they would accumulate for the life
    # of the process.
    def discard_statics(prefix)
      return if prefix.nil?

      STATICS_LOCK.synchronize { STATICS.delete_if { |key, _| key.to_s.start_with?(prefix) } }
    end

    # Wraps an already-escaped or trusted string without copying when possible.
    def safe(value)
      value.is_a?(SafeString) ? value : SafeString.new(value.to_s)
    end

    # Marks a string as trusted HTML. The equivalent of Rails' `html_safe`.
    def raw(value)
      return EMPTY_SAFE if value.nil?

      value.is_a?(SafeString) ? value : SafeString.new(value.to_s)
    end

    def escape(value)
      SafeString.new(Escape.html(value.to_s))
    end

    # dangerouslySetInnerHTML={{ __html: markup }}
    def raw_html(value)
      return EMPTY_SAFE if value.nil?

      html = value.respond_to?(:[]) && !value.is_a?(String) ? (value[:__html] || value["__html"]) : value
      html.nil? ? EMPTY_SAFE : html.to_s
    end

    def json(object)
      require "json"
      JSON.generate(object)
    end

    # ------------------------------------------------------------------
    # Defining components
    # ------------------------------------------------------------------

    # Emitted by `component Name do |props| ... end`.
    def define_component(name, cache: nil, static: false, &body)
      component = Class.new(Component)
      assign_constant(name, component)
      component.cache(cache) if cache
      component.rsx_static! if static
      loader.track(component)
      component.class_eval(&body)
      component
    end

    def create_context(default = nil, name: nil)
      Context.new(default, name: name)
    end

    # Emitted by `import Name from "path"`.
    def import(spec, as: nil, from: nil)
      from = nil if from.to_s.empty?
      loader.import(spec, as: as, from: from)
    end

    # Emitted by `export default Name`.
    def export_default(component, from: nil)
      entry = loader.current_entry || (from && loader.entries.find { |candidate| candidate.path == from })
      entry.default = component if entry
      component
    end

    # Emitted by `export Name`.
    def export(component, from: nil)
      entry = loader.current_entry || (from && loader.entries.find { |candidate| candidate.path == from })
      if entry && !entry.components.include?(component)
        entry.components << component
      end
      component
    end

    # ------------------------------------------------------------------
    # Constants
    # ------------------------------------------------------------------

    def assign_constant(path, value)
      parts = path.to_s.split("::")
      target = config.component_namespace

      parts[0..-2].each do |part|
        target = if target.const_defined?(part, false)
                   target.const_get(part, false)
                 else
                   target.const_set(part, Module.new)
                 end
      end

      last = parts.last
      target.send(:remove_const, last) if target.const_defined?(last, false)
      target.const_set(last, value)
      value
    end

    def constant_defined?(path)
      parts = path.to_s.split("::")
      return false unless parts.all? { |part| part.match?(/\A[A-Z][A-Za-z0-9_]*\z/) }

      target = config.component_namespace
      parts.each do |part|
        return false unless target.is_a?(Module) && target.const_defined?(part, false)

        target = target.const_get(part, false)
      end
      true
    end
    alias const_defined_at? constant_defined?

    def remove_constant(component)
      name = component.name
      return if name.nil?

      parts = name.split("::")
      target = Object
      parts[0..-2].each do |part|
        return unless target.const_defined?(part, false)

        target = target.const_get(part, false)
      end
      last = parts.last
      return unless target.const_defined?(last, false)
      return unless target.const_get(last, false).equal?(component)

      target.send(:remove_const, last)
    end

    # ------------------------------------------------------------------
    # Cache helpers
    # ------------------------------------------------------------------

    def normalize_cache_options(options)
      case options
      when true then {}
      when false, nil then nil
      when Hash then options
      when Numeric then { expires_in: options }
      when Proc then { key: options }
      else raise ArgumentError, "unsupported cache option #{options.inspect}"
      end
    end

    # Builds a short, stable cache key fragment from arbitrary Ruby values.
    def stable_key(object)
      fragment = key_fragment(object)
      fragment.length > 128 ? Digest::SHA256.hexdigest(fragment)[0, 32] : fragment
    end

    def key_fragment(object)
      case object
      when nil then "~"
      when String then object
      when Symbol, Numeric, true, false then object.to_s
      when Array then object.map { |item| key_fragment(item) }.join(",")
      when Hash then object.map { |key, value| "#{key}=#{key_fragment(value)}" }.join("&")
      when Time then object.to_f.to_s
      else
        if object.respond_to?(:cache_key_with_version)
          object.cache_key_with_version.to_s
        elsif object.respond_to?(:cache_key)
          object.cache_key.to_s
        elsif object.respond_to?(:id) && object.respond_to?(:updated_at)
          "#{object.class}/#{object.id}-#{object.updated_at.to_i}"
        else
          object.to_s
        end
      end
    end
  end
end

require_relative "rsx/railtie" if defined?(::Rails::Railtie)

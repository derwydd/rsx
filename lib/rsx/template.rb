# frozen_string_literal: true

module RSX
  # A .rsx file rendered as markup rather than as a named component.
  #
  # The file body becomes a method on an anonymous Component subclass, so a
  # template gets the whole component toolkit (children, caching, context,
  # helpers) and is compiled once no matter how often it is rendered.
  class Template
    attr_reader :path, :digest, :component

    def self.load(path)
      absolute = File.expand_path(path)
      raise FileNotFoundError, "no such RSX file: #{absolute}" unless File.file?(absolute)

      new(File.read(absolute), path: absolute)
    end

    def self.from_ruby(ruby, path: nil, digest: nil)
      allocate.tap { |template| template.send(:build, ruby, path, digest) }
    end

    def initialize(source, path: nil)
      digest = RSX.config.compile_cache.digest(source.to_s)
      ruby = RSX.config.compile_cache.fetch_or_compile(path || "template", source.to_s) do
        Transformer.transform(source.to_s, path: path)
      end
      build(ruby, path, digest)
    end

    def render(props = nil, context: nil)
      value = @component.new(props, context).rsx_render(props)

      # A file whose last statement is a component definition (or an
      # `export default`) renders that component with the props it was given.
      if value.is_a?(Class) && value < Component
        RSX.safe(value.rsx_call(props, context))
      else
        RSX.safe(RSX.child(value))
      end
    end

    private

    def build(ruby, path, digest)
      @path = path
      @digest = digest
      @component = Class.new(Component)
      @component.rsx_source_path = path
      @component.rsx_source_digest = digest

      body = ruby.end_with?("\n") ? ruby : "#{ruby}\n"
      # Evaluating from line 0 puts the generated `def` above line 1, so every
      # line of the template keeps its original number in backtraces.
      @component.class_eval("def rsx_render(props = nil)\n#{body}end\n", path || "(rsx)", 0)
      self
    end
  end
end

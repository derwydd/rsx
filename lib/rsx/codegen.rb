# frozen_string_literal: true

module RSX
  # Turns an RSX node tree into Ruby source.
  #
  # Markup compiles to a single interpolated string literal: static text is baked
  # in at compile time and only the {ruby} parts remain as interpolations. Nested
  # elements are spliced into their parent's literal, so an entire static subtree
  # collapses to one frozen string with no intermediate objects.
  #
  #   <ul className="list"><li>{name}</li></ul>
  #
  # becomes
  #
  #   ::RSX::SafeString.new("<ul class=\"list\"><li>#{::RSX.child(name)}</li></ul>")
  class Codegen
    LITERAL_ESCAPES = {
      "\\" => "\\\\",
      '"' => '\"',
      "\n" => '\n',
      "\t" => '\t',
      "\r" => '\r',
      "\e" => '\e',
      "\0" => '\0'
    }.freeze

    LITERAL_PATTERN = /[\\"\n\t\r\e\0]|#(?=[{$@])/

    INNER_HTML = %w[dangerouslySetInnerHTML dangerously_set_inner_html].freeze

    def initialize(path: nil, prefix: nil)
      @path = path
      @prefix = prefix || "rsx"
      @statics = 0
    end

    # Returns [ruby_source, static?]
    def compile(node, start_line:, end_line:)
      parts = []
      emit(node, parts)
      parts = merge(parts)
      static = parts.all? { |part| part[0] == :static }
      [assemble(parts, start_line, end_line, static), static]
    end

    private

    def emit(node, parts)
      case node
      when Nodes::Text
        parts << [:static, Escape.static_text(node.value), node.line]
      when Nodes::RawText
        parts << [:static, node.value, node.line]
      when Nodes::Expression
        # The extra parentheses let a container hold anything Ruby accepts as an
        # expression, including modifiers: {greeting if signed_in?}.
        parts << [:dynamic, "::RSX.child((#{node.source}))", node.line]
      when Nodes::Fragment
        node.children.each { |child| emit(child, parts) }
      when Nodes::Element
        emit_element(node, parts)
      when Nodes::Component
        emit_component(node, parts)
      else
        raise Error, "unexpected node #{node.inspect}"
      end
    end

    # ------------------------------------------------------------------
    # Elements
    # ------------------------------------------------------------------

    def emit_element(node, parts)
      tag = node.tag
      parts << [:static, "<#{tag}", node.line]

      inner_html = nil
      attributes = node.attributes.reject do |attribute|
        next false unless attribute.kind != :spread && INNER_HTML.include?(attribute.name)

        inner_html = attribute
        true
      end

      if attributes.any? { |attribute| attribute.kind == :spread }
        emit_spread_attributes(attributes, parts)
      else
        dedupe(attributes).each { |attribute| emit_attribute(attribute, parts) }
      end

      if inner_html
        parts << [:static, ">", last_line(parts, node)]
        parts << [:dynamic, "::RSX.raw_html(#{inner_html.value})", inner_html.line]
        parts << [:static, "</#{tag}>", last_line(parts, node)]
        return
      end

      if Attributes.void?(tag)
        parts << [:static, ">", last_line(parts, node)]
        return
      end

      if node.children.empty?
        if node.self_closing && Attributes.self_closing?(tag)
          parts << [:static, "/>", last_line(parts, node)]
        else
          parts << [:static, "></#{tag}>", last_line(parts, node)]
        end
        return
      end

      parts << [:static, ">", last_line(parts, node)]
      node.children.each { |child| emit(child, parts) }
      parts << [:static, "</#{tag}>", last_line(parts, node)]
    end

    # An element with a spread has all of its attributes merged at runtime, so a
    # later value replaces an earlier one exactly as it would in React. Emitting
    # them one by one would instead produce a duplicate HTML attribute, where
    # the browser keeps the first.
    def emit_spread_attributes(attributes, parts)
      groups = []
      attributes.each do |attribute|
        if attribute.kind == :spread
          groups << attribute.value
        elsif groups.last.is_a?(Array)
          groups.last << attribute_pair(attribute)
        else
          groups << [attribute_pair(attribute)]
        end
      end

      source =
        if groups.length == 1 && !groups.first.is_a?(Array)
          "::RSX::Attributes.render_all(#{groups.first})"
        else
          arguments = groups.map { |group| group.is_a?(Array) ? "{ #{group.join(", ")} }" : "(#{group})" }
          "::RSX::Attributes.render_all(::RSX::Attributes.merge(#{arguments.join(", ")}))"
        end

      parts << [:dynamic, source, attributes.first.line]
    end

    # Two props naming the same HTML attribute would otherwise be written twice,
    # which is invalid HTML and inverts the result: React keeps the last value,
    # browsers keep the first. Matches Attributes.merge by holding the first
    # position and taking the last value.
    def dedupe(attributes)
      return attributes if attributes.length < 2

      # Reassigning a Hash key keeps its original position and takes the new
      # value, which is the merge rule verbatim.
      by_name = {}
      attributes.each { |attribute| by_name[Attributes.canonical_name(attribute.name)] = attribute }
      by_name.length == attributes.length ? attributes : by_name.values
    end

    def attribute_pair(attribute)
      key = symbol_literal(attribute.name)

      case attribute.kind
      when :boolean then "#{key} => true"
      when :static then %(#{key} => "#{escape_literal(attribute.value)}")
      when :expression then "#{key} => (#{attribute.value})"
      end
    end

    def emit_attribute(attribute, parts)
      name = Attributes.attribute_name(attribute.name)
      return if name.nil? || name.empty?

      case attribute.kind
      when :boolean
        text = Attributes.boolean?(name) ? " #{name}" : %( #{name}="true")
        parts << [:static, text, attribute.line]
      when :static
        parts << [:static, static_attribute(name, attribute.value), attribute.line]
      when :expression
        parts << [:dynamic, dynamic_attribute(name, attribute.value), attribute.line]
      end
    end

    def static_attribute(name, value)
      %( #{name}="#{Escape.static_text(value)}")
    end

    def dynamic_attribute(name, source)
      case name
      when "class" then "::RSX::Attributes.render_class(#{source})"
      when "style" then "::RSX::Attributes.render_style(#{source})"
      when "data", "aria" then %(::RSX::Attributes.render_nested("#{name}", #{source}))
      else %(::RSX::Attributes.render("#{name}", #{source}))
      end
    end

    # ------------------------------------------------------------------
    # Components
    # ------------------------------------------------------------------

    def emit_component(node, parts)
      source = "::RSX.render_component(#{node.name}, #{props_source(node)}, #{children_source(node)}, self)"
      parts << [:dynamic, source, node.line]
    end

    def props_source(node)
      entries = node.attributes.map do |attribute|
        case attribute.kind
        when :spread then "**(#{attribute.value})"
        when :boolean then "#{symbol_literal(attribute.name)} => true"
        when :static then "#{symbol_literal(attribute.name)} => \"#{escape_literal(attribute.value)}\""
        when :expression then "#{symbol_literal(attribute.name)} => (#{attribute.value})"
        end
      end

      entries.empty? ? "nil" : "{ #{entries.join(", ")} }"
    end

    def symbol_literal(name)
      name.match?(/\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/) ? ":#{name}" : %(:"#{escape_literal(name)}")
    end

    # Children are passed lazily so that components can decide whether (and in
    # what context) to render them: caching, context providers and conditional
    # slots all depend on not having rendered them yet. Fully static children
    # skip the wrapper entirely since there is nothing to defer.
    def children_source(node)
      return "nil" if node.children.empty?

      # A lone {expression} is handed over untouched rather than rendered to a
      # string, so children can be any value: a lambda for a render prop, an
      # array, a model. RSX.child coerces it if the component interpolates it.
      if node.children.length == 1 && node.children.first.is_a?(Nodes::Expression)
        return "::RSX::Children.new { #{node.children.first.source} }"
      end

      parts = []
      node.children.each { |child| emit(child, parts) }
      parts = merge(parts)
      return "nil" if parts.empty?

      static = parts.all? { |part| part[0] == :static }
      body = assemble(parts, parts.first[2], parts.last[2], static)
      static ? body : "::RSX::Children.new { #{body} }"
    end

    # ------------------------------------------------------------------
    # Assembly
    # ------------------------------------------------------------------

    def merge(parts)
      merged = []
      parts.each do |part|
        previous = merged.last
        if part[0] == :static && previous && previous[0] == :static
          previous[1] += part[1]
        else
          merged << part.dup
        end
      end
      merged
    end

    def assemble(parts, start_line, end_line, static)
      buffer = +""

      # Markup with nothing dynamic in it is built once and then reused from a
      # per-call-site slot, so re-rendering it allocates nothing at all. The
      # literal after `||=` is never evaluated again after the first render.
      buffer << "(::RSX::STATICS[#{static_slot}] ||= " if static
      buffer << (static ? "::RSX.static(" : "::RSX::SafeString.new(")
      state = { line: start_line, open: false }

      parts.each do |kind, text, line|
        pad(buffer, state, line)
        open_literal(buffer, state)

        if kind == :static
          buffer << escape_literal(text)
        else
          buffer << '#{' << text << "}"
          state[:line] += text.count("\n")
        end
      end

      open_literal(buffer, state) if parts.empty?
      close_literal(buffer, state)
      pad(buffer, state, end_line)
      buffer << ")"
      buffer << ")" if static
      buffer
    end

    def static_slot
      @statics += 1
      %(:"#{@prefix}#{@statics}")
    end

    # Keeps generated Ruby on the same lines as the .rsx source it came from.
    # Inside a string literal, extra lines are added by closing the literal and
    # continuing it: adjacent literals are concatenated by the parser, so no
    # markup is affected.
    def pad(buffer, state, target)
      count = target - state[:line]
      return if count <= 0

      if state[:open]
        buffer << '" ' << ("\\\n" * count) << '"'
      else
        buffer << ("\n" * count)
      end
      state[:line] = target
    end

    def open_literal(buffer, state)
      return if state[:open]

      buffer << '"'
      state[:open] = true
    end

    def close_literal(buffer, state)
      return unless state[:open]

      buffer << '"'
      state[:open] = false
    end

    def escape_literal(text)
      text.gsub(LITERAL_PATTERN) { |match| LITERAL_ESCAPES[match] || "\\#{match}" }
    end

    def last_line(parts, node)
      parts.empty? ? node.line : parts.last[2]
    end
  end
end

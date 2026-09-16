# frozen_string_literal: true

module RSX
  # Transforms .rsx source (Ruby with embedded JSX-style markup) into plain Ruby.
  #
  # The transformer is a single-pass scanner. Ruby is copied through verbatim
  # while enough lexical state is tracked to know two things:
  #
  #   1. whether a "<" starts markup or is an operator, which comes down to
  #      whether an expression is expected at that position (exactly how Babel
  #      decides that a "<" opens JSX), and
  #   2. where the `end` matching a `component` block is, so the block can be
  #      rewritten into a class definition.
  #
  # Generated Ruby keeps the same line numbering as the source, so exceptions
  # raised inside a template point at the .rsx file and line the user wrote.
  class Transformer
    IDENT_START = /[A-Za-z_]/
    IDENT_CHAR = /[A-Za-z0-9_]/
    TAG_START = /[A-Za-z_>]/
    TAG_CHAR = /[A-Za-z0-9_\-.:]/
    ATTR_START = /[A-Za-z_@]/
    ATTR_CHAR = /[A-Za-z0-9_\-.:]/
    DIGIT = /[0-9]/

    # Keywords after which an expression is expected.
    OPENS_EXPRESSION = %w[
      and begin break case do elsif else ensure if in next not or raise rescue
      return then unless until when while yield
    ].to_h { |word| [word, true] }.freeze

    # Keywords that terminate an expression.
    CLOSES_EXPRESSION = %w[
      end self nil true false __FILE__ __LINE__ __dir__ __method__
    ].to_h { |word| [word, true] }.freeze

    # Keywords that open a block terminated by `end`.
    BLOCK_KEYWORDS = %w[begin case class def module].to_h { |word| [word, true] }.freeze

    # Block keywords that are also statement modifiers (`x if y`).
    MODIFIER_KEYWORDS = %w[if unless while until].to_h { |word| [word, true] }.freeze

    # Appended to compiled output when the file declares components, so a file
    # of components can be told apart from a file of markup without running it.
    COMPONENT_MARKER = "# rsx:components"

    def self.transform(source, path: nil)
      new(source, path: path).transform
    end

    def initialize(source, path: nil)
      @src = source.to_s
      @path = path
      @len = @src.length
      @pos = 0
      @line = 1
      @out_line = 1
      @prev = :start
      @buffers = [+""]
      @heredocs = []
      @blocks = []
      @pending_loop = false
      @jsx_spans = []
      @components = 0
      @preformatted = 0
      @codegen = Codegen.new(path: path, prefix: self.class.static_prefix(@src))
    end

    # Static markup slots are keyed by a digest of the source, so recompiling the
    # same file reuses its slots rather than adding another set. Deriving the
    # prefix from the source alone also lets the loader find and drop the slots
    # belonging to a version of a file it is replacing.
    def self.static_prefix(source)
      "#{Digest::SHA256.hexdigest(source.to_s)[0, 10]}-"
    end

    def transform
      scan(:toplevel)
      unless @blocks.empty?
        component = @blocks.reverse.find { |frame| frame[:kind] == :component }
        if component
          raise SyntaxError.new("unterminated `component #{component[:name]}` block",
                                path: @path, line: component[:line])
        end
      end

      # The marker goes after the last line, so line numbers are unaffected.
      if @components.positive?
        write("\n") unless @buffers.first.empty? || @buffers.first.end_with?("\n")
        write("#{COMPONENT_MARKER}\n")
      end
      @buffers.first
    end

    def self.defines_components?(ruby)
      ruby.include?(COMPONENT_MARKER)
    end

    private

    # ------------------------------------------------------------------
    # Output
    # ------------------------------------------------------------------

    def out
      @buffers.last
    end

    # Copies n characters of source through to the output unchanged.
    def copy(count = 1)
      chunk = @src[@pos, count]
      @pos += chunk.length
      newlines = chunk.count("\n")
      @line += newlines
      @out_line += newlines
      out << chunk
      chunk
    end

    # Writes generated Ruby that has no direct source counterpart.
    def write(text)
      @out_line += text.count("\n")
      out << text
    end

    # Collects output produced by the block instead of appending it.
    def capture
      @buffers.push(+"")
      saved_line = @out_line
      yield
      @out_line = saved_line
      @buffers.pop
    end

    # ------------------------------------------------------------------
    # Character helpers
    # ------------------------------------------------------------------

    def eof?
      @pos >= @len
    end

    def peek(offset = 0)
      @pos + offset < @len ? @src[@pos + offset] : nil
    end

    def lookahead(length, offset = 0)
      @src[@pos + offset, length]
    end

    def advance(count = 1)
      count.times do
        @line += 1 if @src[@pos] == "\n"
        @pos += 1
      end
    end

    def error(message, line: @line)
      raise SyntaxError.new(message, path: @path, line: line)
    end

    # ------------------------------------------------------------------
    # Main scanner
    # ------------------------------------------------------------------

    # mode is :toplevel or :brace. In :brace mode scanning stops (without
    # consuming) at the "}" that closes the current expression container.
    def scan(mode)
      braces = 0

      until eof?
        char = peek

        case char
        when "\n"
          copy
          consume_heredoc_bodies
          @prev = :start
        when " ", "\t", "\r", "\f", "\v"
          copy
        when "#"
          copy_line_comment
        when "'", '"', "`"
          copy_quoted(char)
          @prev = :value
        when "%"
          if @prev == :start && percent_literal?
            copy_percent_literal
            @prev = :value
          else
            copy_operator
          end
        when "<"
          if heredoc_ahead?
            copy_heredoc_header
          elsif @prev == :start && jsx_ahead?
            emit_jsx
          else
            reject_misplaced_markup
            copy_operator
          end
        when "/"
          if @prev == :start
            copy_regex
            @prev = :value
          else
            copy_operator
          end
        when "?"
          if @prev == :start && character_literal?
            copy(2)
            @prev = :value
          else
            copy_operator
          end
        when "{"
          braces += 1
          copy
          @prev = :start
        when "}"
          return if mode == :brace && braces.zero?

          braces -= 1
          copy
          @prev = :value
        when "="
          if block_comment_ahead?
            copy_block_comment
          else
            copy_operator
          end
        else
          if IDENT_START.match?(char) || char == "@" || char == "$"
            scan_word
          elsif DIGIT.match?(char)
            copy_number
            @prev = :value
          else
            copy_operator
          end
        end
      end
    end

    def copy_operator
      char = peek

      # `::` and `?.`-like sequences are copied whole so state stays accurate.
      if char == ":" && peek(1) == ":"
        copy(2)
        @prev = :start
      elsif char == "<" && peek(1) == "<"
        # Reached only when this is not a heredoc, so it is an append: copy both
        # characters at once, or the second one lands in expression position and
        # `list <<x` reads as a tag.
        copy(2)
        @prev = :start
      elsif char == ":" && symbol_ahead?
        copy_symbol
        @prev = :value
      else
        copy
        @prev = case char
                when ")", "]" then :value
                else :start
                end
      end
    end

    def copy_number
      copy while !eof? && /[0-9a-zA-Z_]/.match?(peek)
      if peek == "." && peek(1) && DIGIT.match?(peek(1))
        copy
        copy while !eof? && /[0-9a-zA-Z_]/.match?(peek)
      end
    end

    def copy_line_comment
      copy until eof? || peek == "\n"
    end

    def block_comment_ahead?
      lookahead(6) == "=begin" && at_line_start?
    end

    def at_line_start?
      index = @pos - 1
      index -= 1 while index >= 0 && (@src[index] == " " || @src[index] == "\t")
      index.negative? || @src[index] == "\n"
    end

    def copy_block_comment
      copy until eof? || (peek == "\n" && lookahead(4, 1) == "=end")
      return if eof?

      copy # newline
      copy until eof? || peek == "\n"
    end

    # ------------------------------------------------------------------
    # Literals
    # ------------------------------------------------------------------

    def copy_quoted(quote)
      copy # opening quote
      interpolating = quote != "'"

      until eof?
        char = peek
        if char == "\\"
          copy(2)
        elsif char == quote
          copy
          return
        elsif interpolating && char == "#" && peek(1) == "{"
          copy(2)
          scan(:brace)
          error("unterminated interpolation") if eof?
          copy # closing brace
        else
          copy
        end
      end

      error("unterminated string literal")
    end

    PERCENT_TYPES = "qQwWiIrsx"
    PAIRS = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.freeze

    def percent_literal?
      offset = 1
      offset += 1 if peek(1) && PERCENT_TYPES.include?(peek(1))
      delimiter = peek(offset)
      return false if delimiter.nil?

      !/[A-Za-z0-9\s=]/.match?(delimiter)
    end

    def copy_percent_literal
      copy # %
      copy if PERCENT_TYPES.include?(peek)
      open = peek
      close = PAIRS[open] || open
      nesting = 0
      copy # delimiter

      until eof?
        char = peek
        if char == "\\"
          copy(2)
        elsif char == open && close != open
          nesting += 1
          copy
        elsif char == close
          copy
          return if nesting.zero?

          nesting -= 1
        elsif char == "#" && peek(1) == "{"
          copy(2)
          scan(:brace)
          copy unless eof?
        else
          copy
        end
      end

      error("unterminated %-literal")
    end

    def copy_regex
      copy # opening slash
      in_class = false

      until eof?
        char = peek
        case char
        when "\\" then copy(2)
        when "[" then in_class = true; copy
        when "]" then in_class = false; copy
        when "#"
          if peek(1) == "{"
            copy(2)
            scan(:brace)
            copy unless eof?
          else
            copy
          end
        when "/"
          if in_class
            copy
          else
            copy
            copy while !eof? && /[imxounse]/.match?(peek)
            return
          end
        when "\n"
          error("unterminated regexp literal")
        else copy
        end
      end
    end

    def character_literal?
      after = peek(1)
      return false if after.nil? || /\s/.match?(after)

      following = peek(2)
      following.nil? || !IDENT_CHAR.match?(following)
    end

    def symbol_ahead?
      after = peek(1)
      return false if after.nil?

      IDENT_START.match?(after) || after == '"' || after == "'" || after == "@" || after == "$"
    end

    def copy_symbol
      copy # colon
      if peek == '"' || peek == "'"
        copy_quoted(peek)
        return
      end
      copy while !eof? && (IDENT_CHAR.match?(peek) || peek == "@" || peek == "$")
      copy if peek == "?" || peek == "!" || (peek == "=" && peek(1) != "=" && peek(1) != ">" && peek(1) != "~")
    end

    # ------------------------------------------------------------------
    # Heredocs
    # ------------------------------------------------------------------

    def heredoc_ahead?
      return false unless lookahead(2) == "<<"

      offset = 2
      squiggly = peek(offset) == "~" || peek(offset) == "-"
      offset += 1 if squiggly
      char = peek(offset)
      return false if char.nil?

      if char == '"' || char == "'" || char == "`"
        squiggly || @prev == :start
      elsif IDENT_START.match?(char)
        # A bare `a << B` is a push, not a heredoc, unless an expression is
        # expected here. `<<~` and `<<-` are unambiguous.
        squiggly || (@prev == :start && /[A-Z_]/.match?(char))
      else
        false
      end
    end

    def copy_heredoc_header
      copy(2)
      indented = peek == "~" || peek == "-"
      copy if indented

      quote = (peek == '"' || peek == "'" || peek == "`") ? peek : nil
      copy if quote
      identifier = +""
      while !eof? && IDENT_CHAR.match?(peek)
        identifier << peek
        copy
      end
      copy if quote

      @heredocs << { id: identifier, indented: indented }
      @prev = :value
    end

    def consume_heredoc_bodies
      return if @heredocs.empty?

      pending = @heredocs
      @heredocs = []

      pending.each do |heredoc|
        loop do
          break if eof?

          line_start = @pos
          copy until eof? || peek == "\n"
          text = @src[line_start...@pos]
          copy unless eof?
          terminator = heredoc[:indented] ? text.strip : text.chomp
          break if terminator == heredoc[:id]
        end
      end
    end

    # ------------------------------------------------------------------
    # Words: identifiers, keywords, and RSX statements
    # ------------------------------------------------------------------

    def scan_word
      if peek == "@" || peek == "$"
        copy
        copy while peek == "@"
        copy while !eof? && IDENT_CHAR.match?(peek)
        @prev = :value
        return
      end

      word = read_word_text
      word_start = @pos
      statement_position = @prev == :start

      if statement_position
        case word
        when "component"
          return if try_component_header
        when "import"
          return if try_import
        when "export"
          return if try_export
        end
      end

      copy(word.length)
      copy if (peek == "?" || peek == "!") && peek(1) != "="

      case word
      when "end"
        close_block(word_start)
        @prev = :value
      when "def"
        @blocks.push({ kind: :block, line: @line }) unless endless_def_ahead?
        @prev = :start
      when "do"
        if @pending_loop
          @pending_loop = false
        else
          @blocks.push({ kind: :block, line: @line })
        end
        @prev = :start
      when "while", "until", "for"
        if statement_position
          @blocks.push({ kind: :block, line: @line })
          @pending_loop = true
        end
        @prev = :start
      when "if", "unless"
        @blocks.push({ kind: :block, line: @line }) if statement_position
        @prev = :start
      else
        if BLOCK_KEYWORDS.key?(word)
          @blocks.push({ kind: :block, line: @line })
          @prev = :start
        elsif CLOSES_EXPRESSION.key?(word)
          @prev = :value
        elsif OPENS_EXPRESSION.key?(word)
          @prev = :start
        else
          @prev = :value
        end
      end
    end

    def read_word_text
      offset = 0
      offset += 1 while @pos + offset < @len && IDENT_CHAR.match?(@src[@pos + offset])
      @src[@pos, offset]
    end

    def close_block(body_end)
      frame = @blocks.pop
      return unless frame && frame[:kind] == :component

      write("; #{component_epilogue(frame, body_end)}end")
    end

    def component_epilogue(frame, body_end)
      return "" unless static_component?(frame, body_end)

      "rsx_static!; "
    end

    # A component whose body is nothing but static markup can be rendered once
    # and reused forever, which is the fastest path RSX has.
    def static_component?(frame, body_end)
      body = @src[frame[:body_start]...body_end].dup
      spans = @jsx_spans.select { |span| span[0] >= frame[:body_start] && span[1] <= body_end }
      return false if spans.empty?
      return false unless spans.all? { |span| span[2] }

      spans.reverse_each do |span|
        body[(span[0] - frame[:body_start])...(span[1] - frame[:body_start])] = ""
      end

      # What is left over must be nothing but `return`, grouping parentheses,
      # comments and whitespace for the body to count as purely static.
      leftover = body.gsub(/^[ \t]*#.*$/, "").gsub(/[\s;()]/, "")
      leftover.delete_prefix!("return")
      leftover.empty?
    end

    def endless_def_ahead?
      offset = 0
      offset += 1 while @pos + offset < @len && /[ \t]/.match?(@src[@pos + offset])
      offset += 1 while @pos + offset < @len && /[A-Za-z0-9_.?!\[\]<>=+\-*\/%&|^~]/.match?(@src[@pos + offset])

      if @src[@pos + offset] == "("
        depth = 0
        while @pos + offset < @len
          char = @src[@pos + offset]
          depth += 1 if char == "("
          if char == ")"
            depth -= 1
            if depth.zero?
              offset += 1
              break
            end
          end
          break if char == "\n"

          offset += 1
        end
      end

      offset += 1 while @pos + offset < @len && /[ \t]/.match?(@src[@pos + offset])
      @src[@pos + offset] == "=" && !["=", "~", ">"].include?(@src[@pos + offset + 1])
    end

    # ------------------------------------------------------------------
    # component / import / export statements
    # ------------------------------------------------------------------

    # component Name[, options] do [|params|]
    def try_component_header
      match = /\Acomponent[ \t]+([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)/.match(@src[@pos..])
      unless match
        lowercase = /\Acomponent[ \t]+([a-z_][A-Za-z0-9_]*)/.match(@src[@pos..])
        if lowercase
          error("component names must be constants, got `#{lowercase[1]}` " \
                "(try `component #{lowercase[1].split('_').map(&:capitalize).join}`)")
        end
        return false
      end

      line = @line
      name = match[1]
      start = @pos
      advance(match[0].length)

      options = read_component_options
      if options.nil?
        # No `do` follows, so this was not a component header after all.
        @pos = start
        return false
      end

      params = read_component_params
      body_start = @pos

      write(%(::RSX.define_component("#{name}"#{options}) do; def rsx_render(#{params});))
      @components += 1
      @blocks.push({ kind: :component, name: name, line: line, body_start: body_start })
      @prev = :start
      true
    end

    # Reads any options between the component name and `do`, e.g. `, cache: true`.
    def read_component_options
      start = @pos
      depth = 0

      until eof?
        char = peek
        case char
        when "(", "[", "{" then depth += 1; advance
        when ")", "]", "}" then depth -= 1; advance
        when "'", '"'
          capture { copy_quoted(char) }
        when "#"
          advance until eof? || peek == "\n"
        when "d"
          if depth.zero? && lookahead(2) == "do" && !identifier_char?(peek(2)) && !identifier_char?(@src[@pos - 1])
            options = @src[start...@pos].strip
            advance(2)
            return "" if options.empty?
            return options.start_with?(",") ? options : ", #{options}"
          end
          advance
        else
          advance
        end
      end

      @pos = start
      nil
    end

    def identifier_char?(char)
      !char.nil? && IDENT_CHAR.match?(char)
    end

    def read_component_params
      advance while !eof? && /[ \t]/.match?(peek)
      return "_props = nil" unless peek == "|"

      advance
      start = @pos
      depth = 0

      until eof?
        char = peek
        case char
        when "(", "[", "{" then depth += 1; advance
        when ")", "]", "}" then depth -= 1; advance
        when "'", '"' then capture { copy_quoted(char) }
        when "|"
          if depth.zero?
            params = @src[start...@pos].strip
            advance
            return params.empty? ? "_props = nil" : params
          end
          advance
        when "\n" then error("unterminated component parameter list")
        else advance
        end
      end

      error("unterminated component parameter list")
    end

    # import Name from "path" / import { A, B } from "path" / import "path"
    def try_import
      rest = @src[@pos..][/\A[^\n]*/]
      named = /\Aimport[ \t]+([A-Z][A-Za-z0-9_:]*)[ \t]+from[ \t]+(["'])(.+?)\2[ \t]*;?[ \t]*\z/.match(rest)
      listed = /\Aimport[ \t]+\{([^}]+)\}[ \t]+from[ \t]+(["'])(.+?)\2[ \t]*;?[ \t]*\z/.match(rest)
      bare = /\Aimport[ \t]+(["'])(.+?)\1[ \t]*;?[ \t]*\z/.match(rest)

      if named
        advance(rest.length)
        write(%(::RSX.import("#{named[3]}", as: %i[#{named[1]}], from: __FILE__)))
      elsif listed
        names = listed[1].split(",").map(&:strip).reject(&:empty?)
        advance(rest.length)
        write(%(::RSX.import("#{listed[3]}", as: %i[#{names.join(" ")}], from: __FILE__)))
      elsif bare
        advance(rest.length)
        write(%(::RSX.import("#{bare[2]}", from: __FILE__)))
      else
        return false
      end

      @prev = :value
      true
    end

    # export default Name / export Name
    def try_export
      rest = @src[@pos..][/\A[^\n]*/]
      match = /\Aexport[ \t]+(default[ \t]+)?([A-Z][A-Za-z0-9_:]*)[ \t]*;?[ \t]*\z/.match(rest)
      return false unless match

      advance(rest.length)
      if match[1]
        write(%(::RSX.export_default(#{match[2]}, from: __FILE__)))
      else
        write(%(::RSX.export(#{match[2]}, from: __FILE__)))
      end
      @prev = :value
      true
    end

    # ------------------------------------------------------------------
    # JSX
    # ------------------------------------------------------------------

    def jsx_ahead?
      after = peek(1)
      !after.nil? && TAG_START.match?(after)
    end

    # A tag that opens and closes on one line, used only to recognise a mistake.
    MISPLACED_MARKUP = %r{\A<([A-Za-z][A-Za-z0-9_\-.:]*)(?:[ \t]*/>|[^<>\n]*>)}

    # `render <div>x</div>` is not markup to Ruby, it is a chain of comparisons,
    # because a value already ended the expression. Left alone it compiles to
    # something that fails far from the real mistake, so name it here instead.
    #
    # The check demands a space before `<` and none after, which is how markup is
    # written and how comparisons are not, so `a < b` and `a<b` never reach it.
    def reject_misplaced_markup
      return unless @prev == :value
      return unless /[ \t]/.match?(@src[@pos - 1].to_s)

      match = MISPLACED_MARKUP.match(@src[@pos..])
      return if match.nil?
      return unless match[0].end_with?("/>") || @src.index("</#{match[1]}>", @pos)

      error("markup here needs parentheses: `method(<#{match[1]} ... />)`. Ruby reads a " \
            "`<` that follows a value as a comparison, so the markup never starts.")
    end

    def emit_jsx
      start_pos = @pos
      start_line = @line
      node = parse_node
      end_line = @line
      ruby, static = @codegen.compile(node, start_line: start_line, end_line: end_line)
      @jsx_spans << [start_pos, @pos, static]
      write(ruby)
      @prev = :value
    end

    def parse_node
      line = @line
      advance # <

      if peek == ">"
        advance
        children = parse_children("")
        expect_closing_tag("")
        return Nodes::Fragment.new(children, line)
      end

      tag = read_tag_name
      error("expected a tag name after `<`") if tag.empty?

      attributes = parse_attributes(tag)

      if lookahead(2) == "/>"
        advance(2)
        return build_node(tag, attributes, [], true, line)
      end

      error("expected `>` to close <#{tag}>") unless peek == ">"
      advance

      # Void elements are complete at ">": HTML gives them no closing tag.
      if Attributes.void?(tag)
        reject_void_closing_tag(tag, line)
        return build_node(tag, attributes, [], true, line)
      end

      children =
        if Attributes.raw_text?(tag)
          parse_raw_text(tag)
        else
          parse_element_children(tag)
        end

      expect_closing_tag(tag)
      build_node(tag, attributes, children, false, line)
    end

    def parse_element_children(tag)
      @preformatted += 1 if Attributes.preformatted?(tag)
      parse_children(tag)
    ensure
      @preformatted -= 1 if Attributes.preformatted?(tag)
    end

    # The body of <script> or <style>. HTML treats these as raw text, so nothing
    # inside is markup: `.a > .b`, `if (a < b)` and JavaScript object literals are
    # all just characters. Dynamic content goes through dangerouslySetInnerHTML.
    def parse_raw_text(tag)
      start = @pos
      start_line = @line
      closing = "</#{tag}"

      until eof?
        break if peek == "<" && lookahead(closing.length).to_s.casecmp?(closing)

        advance
      end

      error("unterminated <#{tag}> element", line: start_line) if eof?

      body = @src[start...@pos]
      body.empty? ? [] : [Nodes::RawText.new(body, start_line)]
    end

    # `<br>text</br>` parses as a complete <br> followed by `text</br>`, which is
    # then copied out as Ruby and fails in the generated file instead of here.
    def reject_void_closing_tag(tag, line)
      index = @src.index("<", @pos)
      return if index.nil?
      return unless /\A<\/#{Regexp.escape(tag)}[ \t]*>/i.match?(@src[index..])

      error("<#{tag}> is a void element: it takes no children and has no closing tag. " \
            "Write `<#{tag} />`.", line: line)
    end

    def build_node(tag, attributes, children, self_closing, line)
      if tag == "Fragment" || tag == "React.Fragment" || tag == "RSX::Fragment"
        return Nodes::Fragment.new(children, line)
      end

      if component_tag?(tag)
        Nodes::Component.new(tag, attributes, children, line)
      else
        Nodes::Element.new(tag, attributes, children, self_closing, line)
      end
    end

    def component_tag?(tag)
      /\A[A-Z]/.match?(tag) || tag.include?(".") || tag.include?("::")
    end

    def read_tag_name
      start = @pos
      advance while !eof? && TAG_CHAR.match?(peek)
      @src[start...@pos]
    end

    def parse_attributes(tag)
      attributes = []

      loop do
        skip_tag_whitespace
        error("unterminated <#{tag}> tag") if eof?
        break if peek == ">" || lookahead(2) == "/>"

        line = @line

        if peek == "{"
          attributes << Nodes::Attribute.new(nil, read_spread, :spread, line)
          next
        end

        unless ATTR_START.match?(peek)
          error("unexpected `#{peek}` in <#{tag}> attributes")
        end

        name = read_attribute_name
        skip_tag_whitespace

        unless peek == "="
          attributes << Nodes::Attribute.new(name, true, :boolean, line)
          next
        end

        advance
        skip_tag_whitespace

        case peek
        when '"', "'"
          attributes << Nodes::Attribute.new(name, read_attribute_string, :static, line)
        when "{"
          advance
          source = read_expression
          error("unterminated `{` in <#{tag}> attributes") unless peek == "}"
          advance
          attributes << Nodes::Attribute.new(name, source, :expression, line)
        else
          error("attribute `#{name}` needs a quoted string or a {ruby} expression")
        end
      end

      attributes
    end

    # Whitespace plus the comment styles allowed inside a tag.
    def skip_tag_whitespace
      loop do
        advance while !eof? && /\s/.match?(peek)

        if peek == "#" || lookahead(2) == "//"
          advance until eof? || peek == "\n"
        elsif lookahead(2) == "/*"
          advance(2)
          advance until eof? || lookahead(2) == "*/"
          error("unterminated comment") if eof?
          advance(2)
        else
          return
        end
      end
    end

    def read_attribute_name
      start = @pos
      advance
      advance while !eof? && ATTR_CHAR.match?(peek)
      @src[start...@pos]
    end

    def read_attribute_string
      quote = peek
      advance
      value = +""

      until eof?
        char = peek
        if char == "\\" && (peek(1) == quote || peek(1) == "\\")
          value << peek(1)
          advance(2)
        elsif char == quote
          advance
          return value
        else
          value << char
          advance
        end
      end

      error("unterminated attribute value")
    end

    # Reads a {ruby} container, stopping at the brace that closes it. Scanning
    # always restarts in expression position, so `<` opens a nested tag and `/`
    # opens a regexp no matter what token preceded the surrounding tag.
    def read_expression
      @prev = :start
      capture { scan(:brace) }
    end

    def read_spread
      advance # {
      if lookahead(3) == "..."
        advance(3)
      elsif lookahead(2) == "**"
        advance(2)
      else
        error("spread attributes must be written `{**props}` or `{...props}`")
      end

      source = read_expression
      error("unterminated spread attribute") unless peek == "}"
      advance
      source
    end

    def parse_children(tag)
      children = []
      text = +""
      text_line = @line

      loop do
        error("unterminated <#{tag || ""}> element") if eof?

        if peek == "<"
          flush_text(children, text, text_line)
          text = +""
          break if lookahead(2) == "</"

          children << parse_node
          text_line = @line
        elsif peek == "{"
          flush_text(children, text, text_line)
          text = +""

          if lookahead(3) == "{/*"
            skip_jsx_comment
          else
            line = @line
            advance
            source = read_expression
            error("unterminated `{` expression") unless peek == "}"
            advance
            children << Nodes::Expression.new(source, line) unless source.strip.empty?
          end
          text_line = @line
        else
          text << peek
          advance
        end
      end

      children
    end

    def skip_jsx_comment
      advance(3)
      until eof?
        if lookahead(3) == "*/}"
          advance(3)
          return
        end
        advance
      end
      error("unterminated {/* comment */}")
    end

    def flush_text(children, text, line)
      return if text.empty?

      # Inside <pre> or <textarea> the browser shows whitespace as written, so
      # collapsing it the way JSX does elsewhere would change the output.
      if @preformatted.positive?
        children << Nodes::Text.new(text, line)
        return
      end

      normalized = self.class.normalize_text(text)
      children << Nodes::Text.new(normalized, line) unless normalized.empty?
    end

    # JSX whitespace rules: indentation-only lines disappear, and remaining lines
    # are joined with a single space.
    def self.normalize_text(raw)
      lines = raw.split("\n", -1)
      return lines.first.to_s if lines.length == 1

      kept = []
      lines.each_with_index do |line, index|
        text = line
        text = text.sub(/\A[ \t\r]+/, "") if index.positive?
        text = text.sub(/[ \t\r]+\z/, "") if index < lines.length - 1
        kept << text unless text.empty?
      end
      kept.join(" ")
    end

    def expect_closing_tag(tag)
      error("expected `</#{tag}>`") unless lookahead(2) == "</"
      advance(2)
      closing = read_tag_name
      advance while !eof? && /\s/.match?(peek)
      error("expected `>` in closing tag `</#{closing}`") unless peek == ">"
      advance

      return if closing == tag
      return if tag == "" && closing == ""

      error("closing tag `</#{closing}>` does not match opening tag `<#{tag.empty? ? '' : tag}>`")
    end
  end
end

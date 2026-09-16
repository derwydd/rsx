# frozen_string_literal: true

module RSX
  # The `children` prop of a component element.
  #
  # Children compile to a block rather than a finished string, so they are
  # rendered *inside* the component that received them. That is what lets
  # <Theme.Provider> change what its children see, lets a caching component skip
  # building them at all, and means a component that never renders {children}
  # never pays for them.
  #
  # The block's value is memoized, and kept in its raw form as well, so React's
  # render-prop pattern works: <Consumer>{->(value) { ... }}</Consumer>.
  class Children
    UNSET = Object.new
    private_constant :UNSET

    def initialize(&block)
      @block = block
      @value = UNSET
    end

    # The value the children expression evaluated to, before coercion.
    def value
      @value = @block.call if @value.equal?(UNSET)
      @value
    end

    # The rendered markup. Used whenever children are interpolated as {children}.
    def render
      @render ||= RSX.child(value)
    end
    alias to_rsx render
    alias to_safe_string render

    def to_s
      render.to_s
    end

    def to_str
      render.to_s
    end

    def html_safe?
      true
    end

    # Render props: {children.call(item)} passes a value back to the caller.
    def call(...)
      raw = value
      return raw.call(...) if raw.respond_to?(:call)

      raw
    end

    def empty?
      render.empty?
    end
    alias blank? empty?

    def present?
      !empty?
    end
    alias any? present?

    def length
      render.length
    end

    def ==(other)
      to_s == other.to_s
    end

    def inspect
      "#<RSX::Children #{@render ? @render.inspect : "(not rendered)"}>"
    end
  end
end

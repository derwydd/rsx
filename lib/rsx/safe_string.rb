# frozen_string_literal: true

module RSX
  # An HTML-safe string. Anything wrapped in a SafeString is emitted verbatim;
  # everything else that flows into a template is escaped.
  #
  # SafeString subclasses String so it interoperates with ActionView output
  # buffers, ActiveSupport::SafeBuffer and plain Ruby string operations without
  # requiring ActiveSupport to be loaded.
  class SafeString < String
    def html_safe?
      true
    end

    # Rails calls this when concatenating into an output buffer.
    def to_s
      self
    end

    def to_safe_string
      self
    end

    # Concatenation keeps the safety contract: unsafe operands are escaped.
    def +(other)
      SafeString.new(super(RSX.child(other)))
    end

    def <<(other)
      super(RSX.child(other))
    end
    alias concat <<

    def *(times)
      SafeString.new(super)
    end

    def inspect
      "#<RSX::SafeString #{super}>"
    end
  end
end

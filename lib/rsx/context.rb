# frozen_string_literal: true

module RSX
  # React's Context API: a value provided high in the tree and read anywhere
  # below it without threading props through every component in between.
  #
  #   Theme = RSX.create_context("light")
  #
  #   <Theme.Provider value={"dark"}>
  #     <Toolbar />
  #   </Theme.Provider>
  #
  #   # inside any descendant
  #   {use_context(Theme)}
  #
  # Provided values live on a per-thread stack, so concurrent requests never see
  # each other's context.
  class Context
    attr_reader :name, :default

    def initialize(default = nil, name: nil)
      @default = default
      @name = name
      @key = :"rsx_context_#{object_id}"
    end

    def value
      stack = Thread.current[@key]
      stack && !stack.empty? ? stack.last : @default
    end
    alias current value

    def with(value)
      stack = (Thread.current[@key] ||= [])
      stack.push(value)
      yield
    ensure
      stack.pop
    end

    # Allows <Theme.Provider value={...}>
    def Provider # rubocop:disable Naming/MethodName
      @provider ||= ProviderComponent.new(self)
    end
    alias provider Provider

    def inspect
      "#<RSX::Context #{name || object_id} default=#{@default.inspect}>"
    end

    # A component-like object: anything answering to rsx_call can be rendered.
    class ProviderComponent
      def initialize(context)
        @context = context
      end

      def name
        "#{@context.name || "Context"}.Provider"
      end

      def rsx_call(props = nil, _parent = nil)
        props ||= {}
        @context.with(props[:value]) { RSX.child(props[:children]) }
      end
    end
  end
end

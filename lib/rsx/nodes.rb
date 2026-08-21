# frozen_string_literal: true

module RSX
  # The RSX syntax tree. Every node records the source line it started on so the
  # generated Ruby can be padded to keep backtraces aligned with the .rsx file.
  module Nodes
    # Literal markup text, already whitespace-normalized JSX style.
    Text = Struct.new(:value, :line)

    # {ruby} in child position.
    Expression = Struct.new(:source, :line)

    # <div>, <img />, <my-element>
    Element = Struct.new(:tag, :attributes, :children, :self_closing, :line)

    # <Button>, <Admin::Card>, <Theme.Provider>
    Component = Struct.new(:name, :attributes, :children, :line)

    # <>...</>
    Fragment = Struct.new(:children, :line)

    # kind is :static (name="text"), :expression (name={ruby}),
    # :boolean (bare name) or :spread ({**ruby} / {...ruby}).
    Attribute = Struct.new(:name, :value, :kind, :line)
  end
end

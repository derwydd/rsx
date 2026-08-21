# frozen_string_literal: true

module RSX
  class Error < StandardError; end

  # Raised when a .rsx file cannot be transformed into Ruby.
  class SyntaxError < Error
    attr_reader :path, :line, :column

    def initialize(message, path: nil, line: nil, column: nil)
      @path = path
      @line = line
      @column = column
      location = [path || "(rsx)", line, column].compact.join(":")
      super("#{location}: #{message}")
    end
  end

  # Raised when a <Tag /> cannot be resolved to a component.
  class UnknownComponentError < Error; end

  # Raised when a component is rendered with props it does not accept.
  class PropsError < Error; end

  # Raised when RSX cannot locate a .rsx file for a path or import.
  class FileNotFoundError < Error; end
end

# frozen_string_literal: true

require "cgi/escape"

module RSX
  # HTML escaping. Runtime escaping goes through CGI.escapeHTML (a C extension
  # in stdlib) so no third-party gem is needed.
  module Escape
    # Matches a character reference such as &amp; &#169; or &#x2014;
    ENTITY = /&(?:[a-zA-Z][a-zA-Z0-9]{1,30}|#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6});/

    module_function

    # Escapes text for element content or an attribute value.
    def html(string)
      CGI.escapeHTML(string)
    end

    # True for values that must not be escaped again.
    #
    # ActiveSupport::SafeBuffer (what Rails helpers return) is a String
    # subclass, so the exact-class check below is what keeps `link_to` output
    # from being escaped while still taking the fast path for plain strings.
    def safe?(value)
      return true if value.is_a?(SafeString)
      return false if value.instance_of?(String)

      value.respond_to?(:html_safe?) && value.html_safe?
    end

    # Escaping for *static* text baked in at compile time.
    #
    # JSX passes character references such as &nbsp; through to the browser, so
    # RSX keeps well-formed entities intact while still escaping stray markup.
    def static_text(string)
      return CGI.escapeHTML(string) unless string.include?("&")

      out = +""
      last = 0
      string.scan(ENTITY) do
        match = Regexp.last_match
        out << CGI.escapeHTML(string[last...match.begin(0)])
        out << match[0]
        last = match.end(0)
      end
      out << CGI.escapeHTML(string[last..]) if last < string.length
      out
    end

    # Escapes a value destined for a double-quoted attribute.
    def attribute(value)
      return value if value.is_a?(SafeString)
      return CGI.escapeHTML(value) if value.instance_of?(String)
      return value.to_s if safe?(value)

      CGI.escapeHTML(value.to_s)
    end
  end
end

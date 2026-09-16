# frozen_string_literal: true

module RSX
  # Translates React-style DOM props into HTML attributes.
  #
  # Prop names follow React's conventions (className, htmlFor, tabIndex,
  # strokeWidth, onClick, ...) and are mapped to their HTML spellings. Names that
  # are already lowercase, snake_case or kebab-case pass through unchanged, so
  # idiomatic Ruby markup works too.
  module Attributes
    # React prop => HTML attribute, for names that are not a simple case change.
    PROP_NAMES = {
      "className" => "class",
      "class_name" => "class",
      "htmlFor" => "for",
      "html_for" => "for",
      "httpEquiv" => "http-equiv",
      "acceptCharset" => "accept-charset",
      "charSet" => "charset",
      "tabIndex" => "tabindex",
      "readOnly" => "readonly",
      "maxLength" => "maxlength",
      "minLength" => "minlength",
      "autoComplete" => "autocomplete",
      "autoCapitalize" => "autocapitalize",
      "autoCorrect" => "autocorrect",
      "autoFocus" => "autofocus",
      "autoPlay" => "autoplay",
      "autoSave" => "autosave",
      "crossOrigin" => "crossorigin",
      "dateTime" => "datetime",
      "encType" => "enctype",
      "formAction" => "formaction",
      "formEncType" => "formenctype",
      "formMethod" => "formmethod",
      "formNoValidate" => "formnovalidate",
      "formTarget" => "formtarget",
      "noValidate" => "novalidate",
      "noModule" => "nomodule",
      "srcSet" => "srcset",
      "srcDoc" => "srcdoc",
      "srcLang" => "srclang",
      "hrefLang" => "hreflang",
      "contentEditable" => "contenteditable",
      "spellCheck" => "spellcheck",
      "colSpan" => "colspan",
      "rowSpan" => "rowspan",
      "cellPadding" => "cellpadding",
      "cellSpacing" => "cellspacing",
      "useMap" => "usemap",
      "isMap" => "ismap",
      "allowFullScreen" => "allowfullscreen",
      "allowTransparency" => "allowtransparency",
      "playsInline" => "playsinline",
      "referrerPolicy" => "referrerpolicy",
      "fetchPriority" => "fetchpriority",
      "frameBorder" => "frameborder",
      "marginWidth" => "marginwidth",
      "marginHeight" => "marginheight",
      "mediaGroup" => "mediagroup",
      "inputMode" => "inputmode",
      "enterKeyHint" => "enterkeyhint",
      "imageSizes" => "imagesizes",
      "imageSrcSet" => "imagesrcset",
      "popoverTarget" => "popovertarget",
      "popoverTargetAction" => "popovertargetaction",
      "accessKey" => "accesskey",
      "itemProp" => "itemprop",
      "itemScope" => "itemscope",
      "itemType" => "itemtype",
      "itemID" => "itemid",
      "itemRef" => "itemref",
      "radioGroup" => "radiogroup",
      "defaultValue" => "value",
      "defaultChecked" => "checked",
      "defaultSelected" => "selected"
    }.freeze

    # SVG/MathML attributes whose camelCase spelling is significant.
    CASE_SENSITIVE = %w[
      attributeName attributeType baseFrequency baseProfile calcMode clipPathUnits
      contentScriptType contentStyleType diffuseConstant edgeMode filterRes filterUnits
      glyphRef gradientTransform gradientUnits kernelMatrix kernelUnitLength keyPoints
      keySplines keyTimes lengthAdjust limitingConeAngle markerHeight markerUnits
      markerWidth maskContentUnits maskUnits numOctaves pathLength patternContentUnits
      patternTransform patternUnits pointsAtX pointsAtY pointsAtZ preserveAlpha
      preserveAspectRatio primitiveUnits refX refY repeatCount repeatDur
      requiredExtensions requiredFeatures specularConstant specularExponent spreadMethod
      startOffset stdDeviation stitchTiles surfaceScale systemLanguage tableValues
      targetX targetY textLength viewBox viewTarget xChannelSelector yChannelSelector
      zoomAndPan
    ].to_h { |name| [name, name] }.freeze

    # Attributes rendered bare when truthy and omitted when falsy.
    BOOLEAN = %w[
      allowfullscreen async autofocus autoplay checked controls default defer disabled
      formnovalidate hidden inert ismap itemscope loop multiple muted nomodule novalidate
      open playsinline readonly required reversed selected
    ].to_h { |name| [name, true] }.freeze

    # Elements that must not be given a closing tag.
    VOID = %w[
      area base br col embed hr img input link meta param source track wbr
    ].to_h { |name| [name, true] }.freeze

    # Elements that may legally use XML self-closing syntax in HTML documents.
    SELF_CLOSING = %w[
      circle ellipse line path polygon polyline rect stop use image animate
      animateMotion animateTransform feBlend feColorMatrix feComposite feFlood
      feGaussianBlur feImage feMergeNode feOffset fePointLight feSpotLight feTile
      feTurbulence mpath set
    ].to_h { |name| [name, true] }.freeze

    # CSS properties that take a bare number (everything else gets "px").
    UNITLESS_CSS = %w[
      animation-iteration-count aspect-ratio border-image-outset border-image-slice
      border-image-width box-flex box-flex-group box-ordinal-group column-count columns
      flex flex-grow flex-positive flex-shrink flex-negative flex-order font-weight
      grid-area grid-row grid-row-end grid-row-span grid-row-start grid-column
      grid-column-end grid-column-span grid-column-start line-clamp line-height opacity
      order orphans scale tab-size widows z-index zoom fill-opacity flood-opacity
      stop-opacity stroke-dasharray stroke-dashoffset stroke-miterlimit stroke-opacity
      stroke-width
    ].to_h { |name| [name, true] }.freeze

    # Props that describe the element to RSX rather than to the browser.
    IGNORED = %w[key ref children suppressHydrationWarning].to_h { |name| [name, true] }.freeze

    INVALID_NAME = %r{[\s"'<>/=\0]}
    CAMEL_BOUNDARY = /([a-z0-9])([A-Z])/

    module_function

    # Attribute names are written into the tag verbatim, so a name carrying a
    # quote or a space would end the attribute and start a new one. Values are
    # escaped, but names cannot be, which is why anything malformed is refused
    # rather than mangled into something that still parses as HTML.
    def validate_name!(name)
      return name unless name.empty? || name.match?(INVALID_NAME)

      raise ArgumentError,
            "#{name.inspect} is not a usable HTML attribute name. Attribute names are " \
            "written into the tag as-is, so they cannot come from untrusted input."
    end

    # Maps a prop name to its HTML attribute name, or nil when the prop should
    # not be rendered at all.
    def attribute_name(prop)
      name = prop.to_s
      return nil if IGNORED.key?(name)

      mapped = PROP_NAMES[name]
      return mapped if mapped
      return name if CASE_SENSITIVE.key?(name)
      return name.downcase if name.match?(/\Aon[A-Z]/)
      return name unless name.match?(/[A-Z]/)

      name.gsub(CAMEL_BOUNDARY, '\1-\2').downcase
    end

    def boolean?(name)
      BOOLEAN.key?(name)
    end

    def void?(tag)
      VOID.key?(tag)
    end

    def self_closing?(tag)
      SELF_CLOSING.key?(tag)
    end

    # Renders one attribute, including its leading space: ` href="/x"`.
    def render(name, value)
      case value
      when nil, false then ""
      when true then boolean?(name) ? " #{name}" : %( #{name}="true")
      else %( #{name}="#{Escape.attribute(value)}")
      end
    end

    # class={...} accepts a String, Symbol, Array or Hash.
    def render_class(value)
      tokens = class_tokens(value)
      return "" if tokens.empty?

      %( class="#{Escape.attribute(tokens.join(" "))}")
    end

    def class_tokens(value)
      case value
      when nil, false, true then []
      when String then value.empty? ? [] : [value]
      when Symbol then [value.to_s]
      when Array then value.flat_map { |item| class_tokens(item) }
      when Hash then value.filter_map { |token, on| token.to_s if on }
      else [value.to_s]
      end
    end

    # style={...} accepts a String or a Hash of CSS properties.
    def render_style(value)
      css = style_string(value)
      return "" if css.nil? || css.empty?

      %( style="#{Escape.attribute(css)}")
    end

    def style_string(value)
      case value
      when nil, false, true then nil
      when String then value
      when Array then value.filter_map { |item| style_string(item) }.join(";")
      when Hash
        value.filter_map do |property, raw|
          next if raw.nil? || raw == false || raw == ""

          name = css_property(property)
          "#{name}:#{css_value(name, raw)}"
        end.join(";")
      else value.to_s
      end
    end

    def css_property(property)
      name = property.to_s
      return name unless name.match?(/[A-Z_]/)

      name = name.tr("_", "-")
      name.gsub(CAMEL_BOUNDARY, '\1-\2').downcase
    end

    def css_value(name, value)
      return "#{value}px" if value.is_a?(Numeric) && value != 0 && !UNITLESS_CSS.key?(name)

      value.to_s
    end

    # data={...} / aria={...} expand a Hash into prefixed attributes.
    def render_nested(prefix, value)
      case value
      when nil, false then ""
      when Hash
        value.filter_map do |key, raw|
          next if raw.nil?

          # Like React, data-* and aria-* keep booleans as the strings "true"
          # and "false" rather than becoming bare attributes: ARIA values are
          # enumerated, so `aria-hidden` alone means nothing.
          name = validate_name!("#{prefix}-#{css_property(key)}")
          %( #{name}="#{Escape.attribute(nested_value(raw))}")
        end.join
      else render(prefix, value)
      end
    end

    def nested_value(value)
      case value
      when String, Symbol, Numeric, SafeString then value
      when Array, Hash then RSX.json(value)
      else value.to_s
      end
    end

    # Combines attribute hashes the way React combines props: names that map to
    # the same HTML attribute collapse, keeping the first position and the last
    # value, so `<a {...attrs} className="link">` overrides the spread.
    def merge(*parts)
      merged = {}
      positions = {}

      parts.each do |part|
        next if part.nil? || part == false

        unless part.respond_to?(:each_pair)
          raise ArgumentError, "spread attributes need a Hash, got #{part.class}"
        end

        part.each_pair do |prop, value|
          name = canonical_name(prop)
          existing = positions[name]

          if existing
            merged[existing] = value
          else
            positions[name] = prop
            merged[prop] = value
          end
        end
      end

      merged
    end

    # The name two props have to share to be considered the same attribute.
    def canonical_name(prop)
      attribute_name(prop) || prop.to_s
    end

    # Renders a hash of props as attributes: {**props} / {...props}
    def render_all(hash)
      return "" if hash.nil? || hash == false

      unless hash.respond_to?(:each_pair)
        raise ArgumentError, "spread attributes need a Hash, got #{hash.class}"
      end

      out = +""
      hash.each_pair do |prop, value|
        case prop.to_s
        when "class", "className", "class_name" then out << render_class(value)
        when "style" then out << render_style(value)
        when "data" then out << render_nested("data", value)
        when "aria" then out << render_nested("aria", value)
        when "dangerouslySetInnerHTML" then next
        else
          name = attribute_name(prop)
          next if name.nil? || name.empty?

          out << render(validate_name!(name), value)
        end
      end
      out
    end
  end
end

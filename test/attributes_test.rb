# frozen_string_literal: true

require "test_helper"

# React DOM props mapped onto HTML attributes.
class AttributesTest < Minitest::Test
  include RSXTest

  def test_class_name_becomes_class
    assert_equal %(<p class="a b">x</p>), render(%(<p className="a b">x</p>))
  end

  def test_html_for_becomes_for
    assert_equal %(<label for="email"></label>), render(%(<label htmlFor="email"></label>))
  end

  def test_known_camel_case_props
    assert_equal %(<input tabindex="2" readonly maxlength="8">),
                 render(%(<input tabIndex="2" readOnly maxLength="8" />))
  end

  def test_unknown_camel_case_becomes_kebab_case
    assert_equal %(<svg><path stroke-width="2"></path></svg>),
                 render(%(<svg><path strokeWidth="2"></path></svg>))
  end

  def test_svg_case_sensitive_props_are_preserved
    assert_equal %(<svg viewBox="0 0 16 16"></svg>), render(%(<svg viewBox="0 0 16 16"></svg>))
  end

  def test_event_props_become_lowercase_attributes
    assert_equal %(<button onclick="go()">x</button>),
                 render(%(<button onClick="go()">x</button>))
  end

  def test_boolean_attribute_is_bare_when_true
    assert_equal "<input disabled>", render("<input disabled={true} />")
    assert_equal "<input disabled>", render("<input disabled />")
  end

  def test_false_and_nil_attributes_are_dropped
    assert_equal "<input>", render("<input disabled={false} />")
    assert_equal "<input>", render("<input value={nil} />")
  end

  def test_non_boolean_true_renders_the_string_true
    assert_equal %(<div data-x="true"></div>), render("<div data-x={true}></div>")
  end

  def test_attribute_values_are_escaped
    assert_equal %(<a title="&quot;quoted&quot; &amp; &lt;bad&gt;">x</a>),
                 render(%(<a title={%q{"quoted" & <bad>}}>x</a>))
  end

  def test_class_accepts_an_array
    assert_equal %(<p class="a b">x</p>), render(%(<p className={["a", nil, "b"]}>x</p>))
  end

  def test_class_accepts_a_hash
    assert_equal %(<p class="on">x</p>),
                 render(%(<p className={{ "on" => true, "off" => false }}>x</p>))
  end

  def test_style_accepts_a_hash_with_camel_case_keys
    assert_equal %(<p style="background-color:red;font-size:12px">x</p>),
                 render(%(<p style={{ backgroundColor: "red", fontSize: 12 }}>x</p>))
  end

  def test_style_accepts_snake_case_keys
    assert_equal %(<p style="background-color:red">x</p>),
                 render(%(<p style={{ background_color: "red" }}>x</p>))
  end

  def test_style_leaves_unitless_numbers_alone
    assert_equal %(<p style="z-index:5;line-height:2">x</p>),
                 render(%(<p style={{ zIndex: 5, lineHeight: 2 }}>x</p>))
  end

  def test_style_accepts_a_string
    assert_equal %(<p style="color:red">x</p>), render(%(<p style="color:red">x</p>))
  end

  def test_data_hash_expands
    assert_equal %(<div data-user-id="7" data-open="true" data-closed="false"></div>),
                 render(%(<div data={{ user_id: 7, open: true, closed: false }}></div>))
  end

  def test_nested_hash_drops_nil_values
    assert_equal %(<div aria-label="Close"></div>),
                 render(%(<div aria={{ label: "Close", hidden: nil }}></div>))
  end

  def test_data_hash_serializes_collections_as_json
    assert_equal %(<div data-ids="[1,2]"></div>), render(%(<div data={{ ids: [1, 2] }}></div>))
  end

  def test_aria_hash_expands
    assert_equal %(<div aria-label="Close" aria-hidden="true"></div>),
                 render(%(<div aria={{ label: "Close", hidden: "true" }}></div>))
  end

  def test_spread_with_double_splat
    assert_equal %(<a href="/x" class="link">x</a>),
                 render(%(<a {**{ href: "/x", className: "link" }}>x</a>))
  end

  def test_spread_with_jsx_dots
    assert_equal %(<a href="/x">x</a>), render(%(<a {...{ href: "/x" }}>x</a>))
  end

  def test_later_attributes_win_over_spread
    assert_equal %(<a href="/new">x</a>), render(%(<a {**{ href: "/old" }} href="/new">x</a>))
  end

  def test_spread_wins_over_earlier_attributes
    assert_equal %(<a href="/new">x</a>), render(%(<a href="/old" {**{ href: "/new" }}>x</a>))
  end

  # className and class are the same attribute for merging purposes.
  def test_merging_matches_react_prop_names
    assert_equal %(<a class="link">x</a>), render(%(<a {**{ class: "spread" }} className="link">x</a>))
  end

  def test_a_falsy_override_removes_a_spread_attribute
    assert_equal "<input>", render(%(<input {**{ disabled: true }} disabled={false} />))
  end

  def test_a_nil_spread_is_ignored
    assert_equal %(<a href="/x">x</a>), render(%(<a {**props[:attrs]} href="/x">x</a>), attrs: nil)
  end

  def test_spread_of_a_non_hash_is_rejected
    error = assert_raises(ArgumentError) { render(%(<a {**props[:attrs]} id="x">y</a>), attrs: 5) }
    assert_includes error.message, "spread attributes need a Hash"
  end

  def test_key_and_ref_are_not_rendered
    assert_equal "<li>x</li>", render(%(<li key={1} ref="r">x</li>))
  end

  # Attribute names go into the tag unescaped, so a hash key that closes the
  # quote would otherwise inject an attribute of the attacker's choosing.
  def test_data_keys_cannot_inject_an_attribute
    error = assert_raises(ArgumentError) do
      render(%(<div data={props[:d]}></div>), d: { %(x" onmouseover="alert(1)) => 1 })
    end
    assert_includes error.message, "not a usable HTML attribute name"
  end

  def test_aria_keys_cannot_inject_an_attribute
    assert_raises(ArgumentError) { render(%(<div aria={props[:a]}></div>), a: { "x>y" => 1 }) }
  end

  def test_spread_keys_cannot_inject_an_attribute
    error = assert_raises(ArgumentError) do
      render(%(<div {**props[:attrs]}></div>), attrs: { %(x" onclick="go()) => "1" })
    end
    assert_includes error.message, "not a usable HTML attribute name"
  end

  def test_data_keys_with_legal_punctuation_still_work
    assert_equal %(<div data-a.b="1"></div>), render(%(<div data={props[:d]}></div>), d: { "a.b" => 1 })
  end

  def test_dashed_and_snake_case_attributes_pass_through
    assert_equal %(<div data-controller="modal" my_attr="1"></div>),
                 render(%(<div data-controller="modal" my_attr="1"></div>))
  end

  def test_attribute_expression_may_span_lines
    source = <<~RSX
      <div
        className={[
          "a",
          "b"
        ]}
      ></div>
    RSX
    assert_equal %(<div class="a b"></div>), render(source)
  end
end

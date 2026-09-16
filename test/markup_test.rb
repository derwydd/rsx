# frozen_string_literal: true

require "test_helper"

# Rendering rules for elements, attributes and children.
class MarkupTest < Minitest::Test
  include RSXTest

  def test_renders_a_plain_element
    assert_equal "<p>Hello</p>", render("<p>Hello</p>")
  end

  def test_nests_elements
    assert_equal "<div><span>a</span><span>b</span></div>",
                 render("<div><span>a</span><span>b</span></div>")
  end

  def test_fragment_has_no_wrapper
    assert_equal "<p>a</p><p>b</p>", render("<><p>a</p><p>b</p></>")
  end

  def test_named_fragment
    assert_equal "<i>x</i>", render("<Fragment><i>x</i></Fragment>")
  end

  def test_interpolates_expressions
    assert_equal "<p>2 apples</p>", render("<p>{1 + 1} apples</p>")
  end

  def test_escapes_interpolated_values
    assert_equal "<p>&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;</p>",
                 render(%(<p>{"<script>alert('x')</script>"}</p>))
  end

  def test_does_not_escape_safe_values
    assert_equal "<p><b>bold</b></p>", render(%(<p>{RSX.raw("<b>bold</b>")}</p>))
  end

  def test_nil_false_and_true_render_nothing
    assert_equal "<p></p>", render("<p>{nil}{false}{true}</p>")
  end

  def test_arrays_are_concatenated
    assert_equal "<ul><li>1</li><li>2</li></ul>",
                 render("<ul>{[1, 2].map { |n| <li>{n}</li> }}</ul>")
  end

  def test_void_elements_have_no_closing_tag
    assert_equal %(<img src="/a.png">), render(%(<img src="/a.png" />))
    assert_equal "<br>", render("<br />")
    assert_equal "<hr>", render("<hr>")
  end

  def test_empty_non_void_element_gets_a_closing_tag
    assert_equal "<div></div>", render("<div />")
    assert_equal "<my-widget></my-widget>", render("<my-widget />")
  end

  def test_svg_elements_may_self_close
    assert_equal %(<svg><path d="M0 0"></path></svg>), render(%(<svg><path d="M0 0"></path></svg>))
    assert_equal %(<svg><path d="M0 0"/></svg>), render(%(<svg><path d="M0 0" /></svg>))
  end

  def test_whitespace_between_lines_collapses_like_jsx
    source = <<~RSX
      <p>
        Hello
        world
      </p>
    RSX
    assert_equal "<p>Hello world</p>", render(source)
  end

  def test_whitespace_inside_a_line_is_kept
    assert_equal "<p>a b</p>", render("<p>a b</p>")
    assert_equal "<b>a</b> <i>b</i>", render("<><b>a</b> <i>b</i></>")
  end

  def test_entities_pass_through
    assert_equal "<p>a&nbsp;b &amp; c</p>", render("<p>a&nbsp;b &amp; c</p>")
  end

  def test_stray_ampersand_is_escaped
    assert_equal "<p>Tom &amp; Jerry</p>", render("<p>Tom & Jerry</p>")
  end

  def test_jsx_comments_are_dropped
    assert_equal "<p>ab</p>", render("<p>a{/* not rendered */}b</p>")
  end

  def test_empty_expression_container_renders_nothing
    assert_equal "<p></p>", render("<p>{}</p>")
  end

  def test_dangerously_set_inner_html
    assert_equal "<div><b>raw</b></div>",
                 render(%(<div dangerouslySetInnerHTML={{ __html: "<b>raw</b>" }} />))
  end

  # <script> and <style> are raw text in HTML, so their contents are not markup.
  def test_style_bodies_are_raw_text
    assert_equal "<style>.a > .b { color: red }</style>",
                 render("<style>.a > .b { color: red }</style>")
  end

  def test_script_bodies_are_raw_text
    assert_equal "<script>if (a < b) { f({x: 1}); }</script>",
                 render("<script>if (a < b) { f({x: 1}); }</script>")
  end

  def test_script_body_may_contain_a_closing_tag_in_a_string
    assert_equal %(<script>var a = "</div>";</script>),
                 render(%(<script>var a = "</div>";</script>))
  end

  def test_script_body_is_not_escaped
    assert_equal "<script>a && b</script>", render("<script>a && b</script>")
  end

  def test_empty_script_still_gets_a_closing_tag
    assert_equal %(<script src="/a.js"></script>), render(%(<script src="/a.js"></script>))
  end

  def test_unterminated_raw_text_element_is_reported
    error = assert_raises(RSX::SyntaxError) { render("<script>var a = 1;") }
    assert_includes error.message, "unterminated <script> element"
  end

  def test_dynamic_script_content_goes_through_inner_html
    assert_equal "<script>var a = 1;</script>",
                 render(%(<script dangerouslySetInnerHTML={{ __html: props[:j] }} />), j: "var a = 1;")
  end

  def test_void_elements_reject_a_closing_tag
    error = assert_raises(RSX::SyntaxError) { render("<br></br>") }
    assert_includes error.message, "<br> is a void element"
  end

  def test_void_elements_reject_children
    assert_raises(RSX::SyntaxError) { render(%(<div><img src="a">alt</img></div>)) }
  end

  def test_a_void_element_before_a_closing_tag_is_fine
    assert_equal "<div><br></div>", render("<div><br></div>")
    assert_equal "<div><br><br></div>", render("<div><br /><br /></div>")
  end

  # Whitespace is significant inside <pre> and <textarea>, so JSX's line joining
  # would change what the browser shows.
  def test_pre_preserves_whitespace
    assert_equal "<pre>\n  a\n    b\n</pre>", render("<pre>\n  a\n    b\n</pre>")
  end

  def test_pre_preserves_whitespace_in_nested_elements
    assert_equal "<pre><code>\n  a\n    b\n</code></pre>",
                 render("<pre><code>\n  a\n    b\n</code></pre>")
  end

  def test_textarea_preserves_whitespace
    assert_equal "<textarea>\n  hi\n</textarea>", render("<textarea>\n  hi\n</textarea>")
  end

  def test_pre_still_interpolates
    assert_equal "<pre>\n  v\n</pre>", render("<pre>\n  {props[:x]}\n</pre>", x: "v")
  end

  def test_the_same_element_outside_pre_still_collapses
    assert_equal "<code>a b</code>", render("<code>\n  a\n  b\n</code>")
  end

  def test_multiline_element_with_attributes
    source = <<~RSX
      <a
        href="/x"
        className="link"
      >
        Go
      </a>
    RSX
    assert_equal %(<a href="/x" class="link">Go</a>), render(source)
  end
end

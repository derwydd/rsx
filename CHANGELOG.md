# Changelog

All notable changes to RSX are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

- Publish the gem as `rsx-rb` on RubyGems. The require path remains `rsx`.

### Fixed

- **Attribute name injection.** Hash keys for `data={...}` and `aria={...}` were written into the
  tag without validation, so a key carrying a quote could close the attribute and inject another
  one. Keys that are not usable attribute names now raise `ArgumentError`, in spreads too.
- `<script>` and `<style>` are parsed as raw text, as HTML defines them. CSS selectors with `>`,
  JavaScript comparisons and object literals, and `"</div>"` inside a string no longer break
  compilation. Dynamic content goes through `dangerouslySetInnerHTML`.
- Whitespace inside `<pre>` and `<textarea>` is preserved rather than joined the way JSX joins it,
  which had been changing what the browser displayed.
- A void element given children or a closing tag (`<br></br>`) reports the tag and line instead of
  raising a Ruby syntax error from the generated file.
- Duplicate attributes collapse at compile time keeping the last value, as React does, instead of
  being emitted twice — which was invalid HTML and picked the first value.
- `Proc`, `Method`, `Hash` and `Array` attribute values raise instead of being inspected into the
  document, so `onClick={-> { }}` no longer renders `onclick="#<Proc…>"`.
- Markup in argument position (`wrap <div>x</div>`) reports that it needs parentheses instead of
  compiling to a chain of comparisons that fails elsewhere.
- `list <<x` is an append again; the second `<` was being read as the start of a tag.
- Static markup slots no longer accumulate for the life of the process: the loader drops a file's
  slots when it reloads it. Filling a slot is synchronized, so it is no longer a bare `||=` on a
  Hash shared between threads.
- Template resolution is confined to `.rsx` files inside the configured paths or the working
  directory. It previously accepted absolute paths and `../`, so `render_file` on a value from a
  request could name any file on disk — and loading a template evaluates it.
- `RSX.render_component` copies the props hash instead of writing `:children` into the one it was
  given.

### Added

- `.rsx` templates take part in Rails' template digests, so a `cache` block wrapping an `.rsx`
  partial is invalidated when that partial, or anything it renders, changes.
- `rails generate rsx:component Card title body`.
- CI across supported Rubies and ActionView versions, including a run without Rails, and a job
  that installs the built gem and renders with it. The Rails suite previously skipped in full
  whenever ActionView was absent, which was always.
- RuboCop, configured to the style the code already uses.

### Changed

- `COMPILER_VERSION` is `2`: generated Ruby changed, so cached output from 0.1.0 is recompiled
  automatically on first use.
- `RSX::CompileCache#fetch` is now `fetch_or_compile`, since both arguments identify the entry and
  the old name read like `Hash#fetch`. Internal.

## [0.1.0]

First release.

- `.rsx` templates: JSX syntax with Ruby in place of JavaScript — `<>` fragments, `{}`
  expression containers, `{/* comments */}`, JSX whitespace rules, void and self-closing
  elements.
- Compiler: a single-pass scanner that tells markup apart from Ruby's own uses of `<`
  (comparison, `<<`, heredocs, `class Foo < Bar`) and emits plain Ruby that preserves the
  source's line numbers.
- Attributes: React prop names (`className`, `htmlFor`, `tabIndex`, camelCase SVG), `class`
  and `style` from Strings/Arrays/Hashes, `data`/`aria` hash expansion, HTML boolean
  attributes, React-style spread merging, `dangerouslySetInnerHTML`.
- Components: `component Name do |props|`, keyword and positional props, defaults, required
  props, `**rest`, lazy children, slots, render props, `import`/`export default`, namespaced
  and lambda components.
- Context API: `RSX.create_context`, `<Ctx.Provider>` and `use_context`, scoped per thread.
- Performance: static markup collapsed into frozen literals, automatic static-component
  prerendering, whole-component and fragment caching, on-disk compile cache, `precompile!`.
- Rails: `.html.rsx` template handler, `rsx` and `rsx_file` view helpers, railtie
  configuration, development reloading, `rsx:precompile`, `rsx:clear` and `rsx:components`
  rake tasks.
- `rsx` command line tool: `compile`, `render`, `precompile`, `version`.
- Escaping built on `CGI.escapeHTML` with an `RSX::SafeString` that interoperates with
  `ActiveSupport::SafeBuffer`.

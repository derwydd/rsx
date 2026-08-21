# Changelog

All notable changes to RSX are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

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

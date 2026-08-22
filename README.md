# RSX — JSX for Ruby

RSX is a template language that brings React's JSX authoring model to Ruby. You write `.rsx`
files in which **Ruby replaces JavaScript** and markup is embedded directly in expression
position:

```ruby
component Greeting do |name:, admin: false|
  return (
    <>
      <h1 className="title">Hello, {name}!</h1>
      {admin ? <p>Admin privileges active.</p> : <p>Standard account.</p>}
    </>
  )
end

export default Greeting
```

[Example: RSX with Tailwind CSS](https://github.com/derwydd/rsx-working-example)

Templates are compiled ahead of time into plain Ruby string building, so rendering is
concatenation and escaping — no interpreter, no virtual DOM, no diffing. RSX has **zero runtime
dependencies**; the Rails integration activates itself only when Rails is already loaded.

- [Installation](#installation)
- [Quick start](#quick-start)
- [Two kinds of `.rsx` file](#two-kinds-of-rsx-file)
- [The language](#the-language)
- [Attributes](#attributes)
- [Components](#components)
- [Context](#context)
- [Prerendering and caching](#prerendering-and-caching)
- [Rails integration](#rails-integration)
- [Using RSX without Rails](#using-rsx-without-rails)
- [Command line](#command-line)
- [Configuration reference](#configuration-reference)
- [Differences from React](#differences-from-react)
- [Errors and debugging](#errors-and-debugging)
- [Testing](#testing)

---

## Why RSX

Ruby's view layer has always been a string templating language with tags bolted on (`<%= %>`,
`= ` in Slim, indentation in Haml). JSX took the opposite approach: markup is a first-class
expression in the host language, so ordinary language constructs — variables, methods,
conditionals, loops, composition — are all you need to learn.

RSX is that model, in Ruby:

| Goal | How |
| --- | --- |
| Familiar to anyone who knows JSX | Same syntax: `<>` fragments, `{}` containers, `className`, spread attributes, components as capitalized tags, `import`/`export default` |
| Fast enough for the request path | `.rsx` compiles to Ruby once; static markup collapses into single frozen literals |
| Cacheable like ViewComponent, without being ViewComponent | Whole-component caching, fragment caching, static prerendering, on-disk compile cache |
| Small surface area | No runtime dependencies; ~3k lines of Ruby; the compiler is a single-pass scanner |
| Debuggable | Generated Ruby preserves your line numbers, so backtraces point at the `.rsx` file |

### The example from React, ported

<table>
<tr><th>UserProfile.jsx</th><th>user_profile.rsx</th></tr>
<tr valign="top"><td>

```jsx
function UserProfile() {
  const user = {
    firstName: 'Jane',
    lastName: 'Doe',
    avatarUrl: '...',
    isAdmin: true
  };

  function formatName(n) {
    return `${n.firstName} ${n.lastName}`;
  }

  const alertStyle = {
    color: 'darkred',
    backgroundColor: 'pink'
  };

  return (
    <>
      <h1>Welcome back, {formatName(user)}!</h1>
      <img
        src={user.avatarUrl}
        alt="User profile picture"
        className="profile-image"
      />
      {user.isAdmin ? (
        <p style={alertStyle}>Admin.</p>
      ) : (
        <p>Standard user account.</p>
      )}
    </>
  );
}

export default UserProfile;
```

</td><td>

```ruby
component UserProfile do
  user = {
    first_name: "Jane",
    last_name: "Doe",
    avatar_url: "...",
    is_admin: true
  }

  def format_name(n)
    "#{n[:first_name]} #{n[:last_name]}"
  end

  alert_style = {
    color: "darkred",
    backgroundColor: "pink"
  }

  return (
    <>
      <h1>Welcome back, {format_name(user)}!</h1>
      <img
        src={user[:avatar_url]}
        alt="User profile picture"
        className="profile-image"
      />
      {user[:is_admin] ? (
        <p style={alert_style}>Admin.</p>
      ) : (
        <p>Standard user account.</p>
      )}
    </>
  )
end

export default UserProfile
```

</td></tr>
</table>

The full version lives in [`examples/user_profile.rsx`](examples/user_profile.rsx).

---

## Installation

Add the gem to your Gemfile:

```ruby
gem "rsx"
```

Then:

```bash
bundle install
```

Or install it directly:

```bash
gem install rsx
```

RSX requires **Ruby 3.0+**. It has no runtime dependencies. In a Rails app — ActionView is the
only part RSX touches, and the suite runs against 7.1 — the railtie loads automatically and:

- registers the `.rsx` template handler with ActionView, so `app/views/**/*.html.rsx` just works;
- mixes `RSX::Helpers` into ActionView, giving you `rsx` and `rsx_file`;
- looks for components in `app/components` and `app/rsx`;
- caches compiled output in `tmp/cache/rsx`;
- eager loads components in production and reloads changed files in development;
- adds the `rsx:precompile`, `rsx:clear` and `rsx:components` rake tasks.

Nothing else is required. To change the defaults, see
[Configuration reference](#configuration-reference).

---

## Quick start

### 1. A view

```ruby
# app/views/pages/home.html.rsx
<section className="hero">
  <h1>{@title}</h1>
  <p>Signed in as {current_user.email}</p>
  {link_to "Docs", docs_path, class: "btn"}
</section>
```

Render it from a controller exactly as you would an ERB view:

```ruby
class PagesController < ApplicationController
  def home
    @title = "Welcome"
  end
end
```

Inside a view, `self` is the Rails view context: controller instance variables, `link_to`,
`form_with`, `t`, `render partial:` and every other helper are available directly.

### 2. A component

```ruby
# app/components/badge.rsx
component Badge do |label:, tone: "neutral"|
  return <span className={["badge", "badge-#{tone}"]}>{label}</span>
end

export default Badge
```

Use it from any `.rsx` file by writing it as a tag:

```ruby
# app/views/pages/home.html.rsx
import Badge from "badge"

<p>Status: <Badge label="Live" tone="success" /></p>
```

…or from ERB, Haml or Slim with the `rsx` helper:

```erb
<%= rsx Badge, label: "Live", tone: "success" %>
```

…or from anywhere in Ruby:

```ruby
Badge.call(label: "Live")            # => "<span class=\"badge badge-neutral\">Live</span>"
RSX.render(Badge, label: "Live")     # same, and accepts context:
```

---

## Two kinds of `.rsx` file

This is the only structural concept RSX adds, and it mirrors the difference between a JSX
*module* and a JSX *entry point*.

**A component file** contains one or more `component Name do ... end` declarations. It is
evaluated once, at the top level, exactly like a `.rb` file — so constants, `class`, `def` and
`require` behave normally. Components become constants you can reference anywhere.

```ruby
# app/components/alert.rsx
component Alert do |message:|
  return <div className="alert" role="alert">{message}</div>
end

export default Alert
```

**A template file** contains markup at its top level and no component declarations. Its body is
compiled into a render method, so it can use `props` and — in Rails — the view context.

```ruby
# app/views/posts/show.html.rsx
<article>
  <h1>{@post.title}</h1>
  {@post.body}
</article>
```

RSX decides which is which by looking at the compiled output, so you never declare it. Both
kinds may `import` other files.

> Because the top level of a template file is Ruby, `{...}` there is a Ruby hash, not an
> expression container. Expression containers only exist *inside* markup. Write plain Ruby at
> the top level:
>
> ```ruby
> # not this:  {@post ? <article /> : <p>None</p>}
> @post ? <article>{@post.title}</article> : <p>None</p>
> ```

---

## The language

Everything below is compiled at load time. There is no runtime template parsing.

### Markup in expression position

A `<` begins markup wherever Ruby expects a value: after `return`, `=`, `(`, `,`, `&&`, inside a
block, and so on. Everywhere else `<` stays a Ruby operator, so `a < b`, `a << b`, `a <=> b`,
`class Foo < Bar` and heredocs (`<<~SQL`) are untouched.

```ruby
title  = <h1>Hi</h1>                      # assignment
rows   = items.map { |i| <li>{i}</li> }   # block body
return <p>{n < 10 ? "few" : "many"}</p>   # comparison inside a container
```

### Fragments

Multiple sibling elements need one parent. Use `<>...</>` when you do not want a wrapper
element (`<Fragment>` and `<React.Fragment>` are accepted too):

```ruby
return (
  <>
    <dt>Term</dt>
    <dd>Definition</dd>
  </>
)
```

### Expression containers

`{}` inside markup interpolates any Ruby expression. Values are escaped unless already marked
safe. Following React: `nil`, `true` and `false` render nothing, arrays are concatenated, and
everything else is converted with `to_s`.

```ruby
<p>{user.name}</p>
<p>{format("%.2f", total)}</p>
<p>{items.sum { |i| i.price }}</p>
<p>{"admin" if user.admin?}</p>
```

### Conditionals

Any Ruby conditional works, because a container holds an expression:

```ruby
<div>
  {user.admin? ? <Admin /> : <Standard />}      {/* ternary, as in JSX */}
  {user.admin? && <p>Danger zone</p>}           {/* && shortcut, as in JSX */}
  {notice.presence && <Alert message={notice} />}

  {if user.admin?                               {/* or an if/else expression */}
    <Admin />
  elsif user.staff?
    <Staff />
  else
    <Standard />
  end}

  {case status
   when :ok then <Ok />
   when :error then <Err />
   end}
</div>
```

### Lists

Return markup from any enumerable method. `key` is accepted (for parity with JSX) and not
rendered:

```ruby
<ul>
  {users.map { |user| <li key={user.id}>{user.name}</li> }}
</ul>

<tbody>
  {rows.each_with_index.map do |row, index|
    <tr className={index.even? ? "even" : "odd"}>
      <td>{row.label}</td>
    </tr>
  end}
</tbody>
```

### Comments

`{/* ... */}` inside markup is removed at compile time, and Ruby `#` comments work in Ruby
position (including inside a tag's attribute list):

```ruby
<div>
  {/* not emitted */}
  <img
    src={url}
    alt=""        # a Ruby comment, also fine here
  />
</div>
```

### Text and whitespace

RSX applies JSX's whitespace rules: indentation-only lines are dropped and remaining lines are
joined with a single space. So this…

```ruby
<p>
  Hello,
  world
</p>
```

…renders `<p>Hello, world</p>`. Use `{" "}` when you need a space JSX would have collapsed.

### Escaping and raw HTML

Interpolated values are HTML-escaped. Strings already marked safe (RSX's own output, and
anything answering `html_safe?`, such as `ActiveSupport::SafeBuffer`) pass through untouched.

```ruby
<p>{"<b>"}</p>                                          # => <p>&lt;b&gt;</p>
<p>{raw("<b>bold</b>")}</p>                             # => <p><b>bold</b></p>
<div dangerouslySetInnerHTML={{ __html: markdown }} />   # React's escape hatch
```

---

## Attributes

Attribute values are either a quoted string or a `{ruby}` container. As in JSX, never both
(`className="{x}"` is a literal string).

### Names

React's prop spellings are translated to HTML: `className` → `class`, `htmlFor` → `for`,
`tabIndex` → `tabindex`, `httpEquiv` → `http-equiv`, `strokeWidth` → `stroke-width`, and so on.
Case-sensitive SVG attributes (`viewBox`, `preserveAspectRatio`, …) keep their spelling. Names
that are already lowercase, `snake_case` or `kebab-case` pass through unchanged, so
`data-controller="modal"` works as written.

```ruby
<label htmlFor="email" className="lbl">Email</label>
# => <label for="email" class="lbl">Email</label>
```

### `className`

Accepts a String, Symbol, Array or Hash, and flattens nested combinations. Hash keys are
included when their value is truthy:

```ruby
<div className={["card", size, { selected: selected?, "is-new" => new? }]}></div>
```

### `style`

Accepts a String or a Hash of CSS properties. `camelCase` and `snake_case` keys become
`kebab-case`, and numbers get `px` unless the property is unitless (`z-index`, `line-height`,
`opacity`, `flex-grow`, …):

```ruby
<p style={{ backgroundColor: "pink", marginTop: 8, zIndex: 3 }}></p>
# => <p style="background-color:pink;margin-top:8px;z-index:3"></p>
```

### Booleans

HTML boolean attributes are rendered bare when truthy and dropped when falsy. Non-boolean
attributes given `true` render `="true"`:

```ruby
<input type="checkbox" checked disabled={false} required={true} />
# => <input type="checkbox" checked required>
```

### `data` and `aria`

Pass a Hash to expand it into prefixed attributes. Arrays and Hashes are serialized as JSON.
Following React, booleans become the strings `"true"`/`"false"`, and `nil` drops the attribute:

```ruby
<div data={{ user_id: 7, ids: [1, 2] }} aria={{ label: "Close", hidden: true }}></div>
# => <div data-user-id="7" data-ids="[1,2]" aria-label="Close" aria-hidden="true"></div>
```

### Spread

Both the JSX and the Ruby spelling are accepted:

```ruby
<a {...attrs} className="link">x</a>
<a {**attrs} className="link">x</a>
```

Attributes on an element with a spread are merged the way React merges props: names that map to
the same HTML attribute collapse, keeping the last value. So `className="link"` above overrides
a `class` or `className` coming from `attrs`, rather than emitting the attribute twice. A `nil`
or `false` spread contributes nothing.

Spread works on components too, where it becomes keyword arguments.

### Event handlers

There is no client-side runtime, so handlers are strings — the value of an HTML attribute:

```ruby
<button onClick={"openSettings()"}>Settings</button>
# => <button onclick="openSettings()">Settings</button>
```

For real interactivity, use the attributes your JS framework expects
(`data-controller`, `data-action`, `hx-post`, …) — they pass through untouched.

### Void and self-closing elements

Void elements never get a closing tag, whether or not you write `/`:

```ruby
<br />        # => <br>
<img src={u}> # => <img src="...">
<circle r={4} />  # SVG keeps XML self-closing syntax => <circle r="4"/>
```

---

## Components

### Defining

```ruby
component Name[, options] do |parameters|
  ...
  return <markup />
end
```

The block body becomes the component's render method, so `return` is optional but reads well
with a parenthesized markup block. Component names must be constants; nesting is supported
(`component Admin::Panel do`).

### Props

Declare props as **keyword parameters** — required, optional with defaults, or collected:

```ruby
component Button do |label:, variant: "primary", disabled: false, **rest|
  return <button className={["btn", "btn-#{variant}"]} disabled={disabled} {**rest}>{label}</button>
end
```

- `label:` is required. Omitting it raises `RSX::PropsError` naming the component.
- `variant:` has a default.
- `**rest` collects anything else, so callers can add `id`, `data-*` or `aria` attributes
  without the component knowing about them.
- Without `**rest`, passing an undeclared prop raises `RSX::PropsError` listing what *is*
  declared. This is RSX's substitute for `propTypes`: mistakes surface immediately.

For a component that just forwards everything, take a single positional parameter and read the
props hash:

```ruby
component Debug do |props|
  return <pre>{props.inspect}</pre>
end
```

### Children

Markup nested inside a component tag arrives as the `children:` prop:

```ruby
component Card do |title:, children: nil|
  return (
    <section className="card">
      <h2>{title}</h2>
      <div className="card-body">{children}</div>
    </section>
  )
end
```

```ruby
<Card title="Hello">
  <p>Anything at all.</p>
</Card>
```

Children are **lazy**: they are rendered when interpolated, not when passed. That is what makes
context providers, caching and conditional slots work correctly. `children?` tells you whether
any were given:

```ruby
component Panel do |children: nil|
  return <div>{children? ? children : <p className="empty">Nothing here</p>}</div>
end
```

### Slots

A slot is just a prop holding markup, so no extra API is needed:

```ruby
<Card title="Report" footer={<a href="/export">Export</a>}>
  <Chart data={@data} />
</Card>
```

### Render props

If the only child is an expression, it is passed through unrendered — so a lambda child becomes
a render prop, as in React:

```ruby
component List do |items:, children: nil|
  return <ul>{items.map { |item| <li>{children.call(item)}</li> }}</ul>
end
```

```ruby
<List items={@users}>
  {->(user) { <a href={user_path(user)}>{user.name}</a> }}
</List>
```

### Composition, `import` and `export`

Files reference each other with JSX's module syntax. Paths are resolved against the configured
paths (and relative to the importing file), with the `.rsx` and `.html.rsx` extensions optional:

```ruby
import Button from "components/button"        # default export, bound to `Button`
import { Card, CardList } from "components/card"
import "components/registers_many_components"  # load for side effects

component Toolbar do |props|
  return <div><Button label="Save" /><Card title="Recent" /></div>
end

export default Toolbar   # what `import X from "..."` binds
export Toolbar           # also part of this file's public list
```

Components are plain constants, so `import` is a convenience, not a requirement: anything
already loaded (in Rails, everything under the configured paths) can be used by name. Dotted and
namespaced tags work too: `<Admin::Panel />`, `<Layout.Header />`.

Any object that responds to `rsx_call(props, parent)` can be rendered as a tag, and a `Proc` can
be used as a component:

```ruby
Spacer = ->(props) { <hr className="spacer" /> }
```

### Rendering from Ruby

```ruby
Badge.call(label: "Live")                 # keyword props
Badge.render(label: "Live")               # alias
RSX.render(Badge, label: "Live")          # component, lambda, or name
RSX.render("components/badge", label: "x")# a file path
RSX.render_file("app/views/x.html.rsx")   # a template file
RSX.render_source("<p>{props[:a]}</p>", a: 1)  # source, handy in tests
```

All of them return an `RSX::SafeString`, which reports `html_safe?` and escapes anything unsafe
concatenated onto it.

---

## Context

React's Context API, for values that would otherwise be threaded through every component:

```ruby
# app/components/theme.rsx
Theme = RSX.create_context("light", name: "Theme")

component ThemedPanel do |children: nil|
  theme = use_context(Theme)
  return <div className={["panel", "panel-#{theme}"]}>{children}</div>
end
```

```ruby
<Theme.Provider value={"dark"}>
  <ThemedPanel>Rendered dark, however deep it is nested.</ThemedPanel>
</Theme.Provider>
```

Provided values live on a per-thread stack and are popped when the provider finishes, so
concurrent requests never observe each other's context. Outside any provider, `use_context`
returns the default. You can also push a value from plain Ruby:

```ruby
Theme.with("dark") { render_something }
Theme.value  # => "light" again
```

---

## Prerendering and caching

RSX is built so that a request pays for as little as possible. There are four layers, from
cheapest to most general.

### 1. Compilation happens before the request

`.rsx` is transformed into Ruby once and cached on disk (`tmp/cache/rsx` in Rails), keyed by a
digest of the source and the compiler version. Warm it at deploy time:

```bash
bin/rails rsx:precompile
```

In production the railtie also eager loads every component at boot, so no request ever compiles
a template. `RSX.precompile!` does the same thing outside of rake.

### 2. Static markup collapses into one frozen literal

Markup with no interpolation becomes a single string, allocated once per call site and reused
for the life of the process:

```ruby
# source
<div className="card"><h1>Hi</h1></div>

# compiled
(::RSX::STATICS[:"1c4f972a7c-1"] ||= ::RSX.static("<div class=\"card\"><h1>Hi</h1></div>"))
```

Dynamic markup keeps its static parts inline, so there is one string build and no intermediate
objects per element:

```ruby
# source
<p>{name}</p>

# compiled
::RSX::SafeString.new("<p>#{::RSX.child((name))}</p>")
```

### 3. Static components render once

When a component's body is nothing but static markup, the compiler marks it and its output is
memoized after the first render. This is automatic; `static: true` states it explicitly:

```ruby
component Divider, static: true do
  return <hr className="rule" />
end
```

### 4. Component and fragment caching

Cache a whole component, keyed by its props plus a digest of its source file (so editing the
component invalidates its entries):

```ruby
component Sidebar, cache: { expires_in: 300 } do |section:|
  ...
end
```

`cache:` accepts `true`, a number of seconds, a Hash of `expires_in:`/`key:`, or a lambda used
as the key:

```ruby
component UserCard, cache: { key: ->(props) { [props[:user], I18n.locale] }, expires_in: 1.hour } do |user:|
  ...
end
```

Cache just the expensive part of a body with the `cache` helper:

```ruby
component Page do |user:|
  return (
    <div>
      <h1>{user.name}</h1>
      {cache(["stats", user], expires_in: 60) do
        <ExpensiveStats user={user} />
      end}
    </div>
  )
end
```

Cache keys are built from any Ruby value, using `cache_key_with_version` / `cache_key` /
`id`+`updated_at` when available — so passing an ActiveRecord model does the right thing.

### Cache stores

The default store is a thread-safe in-process LRU (`RSX::Cache::Memory`), which needs no
configuration. In Rails, point RSX at `Rails.cache` to share invalidation with the rest of the
app:

```ruby
config.rsx.cache_store = :rails    # or :memory, :null, or any object with fetch/read/write/clear
```

Anything responding to `fetch(key, expires_in:) { }`, `read`, `write`, `delete` and `clear`
qualifies, so Redis or Memcached need no adapter.

---

## Rails integration

### Views, partials and layouts

Any view, partial or layout can be `.html.rsx`. Inside one, `self` is the view context:

```ruby
# app/views/posts/show.html.rsx
<article className="post">
  <h1>{@post.title}</h1>
  {render(partial: "posts/byline", locals: { author: @post.author })}
  <footer>{link_to "All posts", posts_path}</footer>
</article>
```

```ruby
# app/views/posts/_byline.html.rsx
<p className="byline" data={{ author_id: author.id }}>{author.name}</p>
```

Partial locals are local variables, exactly as in ERB. Output is html-safe, so `.rsx` and ERB
templates can render each other freely.

### Components from ERB, Haml or Slim

```erb
<%= rsx Badge, label: "Live" %>
<%= rsx "Badge", label: "Live" %>            <%# by name, autoloaded on demand %>

<%= rsx Card, title: "Hello" do %>
  <p>This ERB block becomes the component's children.</p>
<% end %>

<%= rsx_file "views/marketing/hero", plan: @plan %>
```

### Rails helpers from inside a component

Components are not views, so they get the view context explicitly through `helpers` (aliased
`view_context`) — the nearest non-component ancestor:

```ruby
component PostLink do |post:|
  return <a href={helpers.post_path(post)}>{post.title}</a>
end
```

`helpers?` reports whether one is available. When you render a component outside a request, pass
one in: `RSX.render(PostLink, context: view, post: post)`.

### Configuration

```ruby
# config/application.rb
config.rsx.paths = [Rails.root.join("app/components"), Rails.root.join("app/rsx")]
config.rsx.cache_store = :rails
config.rsx.cache_dir = Rails.root.join("tmp/cache/rsx")
config.rsx.component_namespace = Object   # e.g. Components to namespace every component
config.rsx.reload = !Rails.env.production?
```

Directories on `config.rsx.paths` are added to Rails' file watcher, so editing a component in
development reloads just that file.

### Rake tasks

```bash
bin/rails rsx:precompile   # compile every .rsx file and warm the on-disk cache
bin/rails rsx:clear        # delete compiled output and clear the render cache
bin/rails rsx:components   # list every file and the components it defines
```

---

## Using RSX without Rails

RSX is a plain Ruby library; nothing above requires Rails.

```ruby
require "rsx"

RSX.configure do |config|
  config.paths = ["components"]
  config.cache_dir = "tmp/rsx"          # nil to compile in memory only
  config.cache_store = RSX::Cache::Memory.new
end

RSX.load("components/badge.rsx")        # or RSX.load_all
puts Badge.call(label: "Live")
puts RSX.render_file("pages/index.rsx", title: "Home")
```

In Sinatra, Roda or Rack, `RSX.render_file(path, context: self, **props)` is usually all you
need — the context object is what `helpers` returns inside components.

---

## Command line

```bash
rsx compile app/components/button.rsx    # print the Ruby a file compiles to
rsx render app/views/home.html.rsx -p title=Hi
rsx precompile app                       # warm the on-disk compile cache
rsx version
```

Options: `-I/--include PATH` adds a directory to the load path, `-c/--cache-dir DIR` chooses
where compiled output goes, `-p/--prop NAME=VALUE` passes a string prop.

`rsx compile` is the fastest way to understand what RSX is doing — the output is ordinary Ruby.

---

## Configuration reference

| Setting | Default | Meaning |
| --- | --- | --- |
| `paths` | `app/components`, `app/rsx` (Rails) | Directories searched for `.rsx` files and imports |
| `cache_dir` | `tmp/cache/rsx` | Where compiled Ruby is stored; `nil` compiles in memory |
| `cache_store` | `RSX::Cache::Memory` | Store for component and fragment caches |
| `component_namespace` | `Object` | Module that `component Name` constants are defined under |
| `reload` | `true` outside production | Reload changed `.rsx` files between requests |

Useful entry points on the `RSX` module: `compile`, `load`, `load_all`, `reload!`,
`precompile!`, `render`, `render_file`, `render_source`, `template`, `lookup_component`,
`create_context`, `cache`, `config`, `configure`, `reset!`.

---

## Differences from React

RSX mirrors JSX's *authoring* model completely. It is not a client-side framework, so the
runtime differences are worth stating plainly:

- **Server-side only.** There is no state, no hooks, no effects, no re-rendering. A component is
  a function from props to HTML. `useState`, `useEffect` and friends have no analogue.
- **Event handlers are strings**, not functions: `onClick={"submit()"}` becomes an `onclick`
  attribute. Pair RSX with Hotwire, Stimulus, htmx or Alpine for behavior.
- **`key` is accepted and ignored.** There is no reconciliation to help.
- **Ruby, not JavaScript**, inside `{}` — so `user[:name]` rather than `user.name` for hashes,
  `&&`/`||` semantics differ around `0` and `""`, and `nil` replaces `null`/`undefined`.
- **Expression containers only exist inside markup.** At the top level of a template file, `{}`
  is a Ruby hash.
- **Whitespace, escaping, fragments, spread, `dangerouslySetInnerHTML`, `className`/`style`
  handling, boolean and `data`/`aria` attributes, children, render props, context, and
  `import`/`export default`** all behave as they do in React.

---

## Errors and debugging

Compiled Ruby preserves the line numbers of the original `.rsx` file, so exceptions raised while
rendering point at the source you wrote:

```
app/components/user_table.rsx:14:in `rsx_render': undefined method `name' for nil (NoMethodError)
```

RSX raises a small set of errors, all descending from `RSX::Error`:

| Error | Cause |
| --- | --- |
| `RSX::SyntaxError` | Malformed markup, with file and line: unterminated tag, missing `}`, unclosed element |
| `RSX::PropsError` | A missing required prop, or an undeclared prop on a component without `**rest` |
| `RSX::UnknownComponentError` | A tag that resolves to nothing renderable |
| `RSX::FileNotFoundError` | An `import` or path that cannot be resolved, listing where RSX looked |

When something renders unexpectedly, `rsx compile FILE` (or `RSX.compile(source)`) shows the
generated Ruby, which is usually enough to see what happened.

---

## Testing

Components are plain Ruby objects, so they can be tested without a request or a view:

```ruby
require "rsx"

class BadgeTest < Minitest::Test
  def setup
    RSX.config.paths = ["app/components"]
    RSX.load("app/components/badge.rsx")
  end

  def test_renders_the_label
    assert_equal %(<span class="badge badge-neutral">Live</span>), Badge.call(label: "Live").to_s
  end
end
```

`RSX.render_source` renders a string of `.rsx` directly, which keeps markup tests to one line:

```ruby
assert_equal "<p>&lt;b&gt;</p>", RSX.render_source("<p>{props[:x]}</p>", x: "<b>").to_s
```

RSX's own suite (compiler, runtime, components, caching, Rails integration, and every file in
`examples/`) runs with:

```bash
rake test
```

---

## Examples

| File | Shows |
| --- | --- |
| [`examples/user_profile.rsx`](examples/user_profile.rsx) | The React example above, ported: variables, methods, inline styles, ternaries |
| [`examples/components/button.rsx`](examples/components/button.rsx) | Prop defaults, required props, pass-through `**rest` |
| [`examples/components/card.rsx`](examples/components/card.rsx) | Children and markup-valued slot props |
| [`examples/components/user_table.rsx`](examples/components/user_table.rsx) | Loops, computed classes, inline styles, helper methods, empty states |
| [`examples/components/sidebar.rsx`](examples/components/sidebar.rsx) | Component caching and fragment caching |
| [`examples/components/theme.rsx`](examples/components/theme.rsx) | Context providers and consumers |
| [`examples/views/dashboard.html.rsx`](examples/views/dashboard.html.rsx) | A Rails view composing all of the above |

---

## License

MIT. See [LICENSE.txt](LICENSE.txt).

# Caching. Two levels are available:
#
#   1. `cache:` on the component caches its entire output, keyed by its props.
#   2. `cache(key) { ... }` inside a body caches one fragment, which is useful
#      when only part of the markup is expensive.
#
# Both keys include a digest of this file, so editing the component invalidates
# what it cached.

component Sidebar, cache: { expires_in: 300 } do |section:, unread: 0|
  return (
    <nav className="sidebar" aria={{ label: "Primary" }}>
      <ul>
        {%w[dashboard projects reports settings].map do |name|
          <li key={name} className={{ current: name == section }}>
            <a href={"/#{name}"}>{name.capitalize}</a>
          </li>
        end}
      </ul>

      {/* Expensive, but only worth caching for a minute */}
      {cache(["sidebar-unread", unread], expires_in: 60) do
        <p className="unread">{unread} unread</p>
      end}
    </nav>
  )
end

export default Sidebar

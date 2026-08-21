# Composition: children plus "slot" props that are themselves markup.
#
# Because attribute values can be any Ruby expression, a slot is just a prop
# that happens to hold markup: <Card header={<h1>Title</h1>}>.

component Card do |title: nil, header: nil, footer: nil, children: nil|
  return (
    <section className="card">
      {/* A header prop wins over the plain title, like a slot overriding a default */}
      <header className="card-header">
        {header || (title && <h2 className="card-title">{title}</h2>)}
      </header>

      <div className="card-body">{children}</div>

      {footer && <footer className="card-footer">{footer}</footer>}
    </section>
  )
end

export default Card

<article className="post">
  <h1>{@title}</h1>
  <p className="intro">{@intro}</p>
  {render(partial: "demo/row", locals: { name: "Ada" })}
  <footer>{link_to("Home", "/")}</footer>
</article>

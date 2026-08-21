import FixtureButton from "fixture_button"

component FixturePage do |title:|
  return (
    <main className="page">
      <h1>{title}</h1>
      <FixtureButton label="Go" variant="danger" />
    </main>
  )
end

export default FixturePage

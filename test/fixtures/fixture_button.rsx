component FixtureButton do |label:, variant: "primary"|
  return <button className={["btn", "btn-#{variant}"]}>{label}</button>
end

export default FixtureButton

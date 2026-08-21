# Context: pass a value down the tree without threading it through props.

Theme = RSX.create_context("light", name: "Theme")

component ThemedPanel do |children: nil|
  theme = use_context(Theme)

  return (
    <div className={["panel", "panel-#{theme}"]} data={{ theme: theme }}>
      {children}
    </div>
  )
end

# Anything rendered inside <Theme.Provider value={"dark"}> sees "dark",
# including components several levels down.
component ThemeDemo do |props|
  return (
    <>
      <ThemedPanel>Uses the default theme.</ThemedPanel>

      <Theme.Provider value={"dark"}>
        <ThemedPanel>Dark, because of the provider above.</ThemedPanel>
      </Theme.Provider>
    </>
  )
end

export default ThemeDemo

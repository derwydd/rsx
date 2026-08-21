# A small component with typed props, defaults and pass-through attributes.
#
# Required props are declared as required keywords, optional ones get defaults,
# and `**rest` collects anything else so callers can add ids, data attributes or
# aria attributes without the component knowing about them.

component Button do |label: nil, variant: "primary", size: "md", disabled: false, children: nil, **rest|
  classes = ["btn", "btn-#{variant}", "btn-#{size}"]

  return (
    <button
      className={classes}
      disabled={disabled}
      aria={disabled ? { disabled: true } : nil}
      {**rest}
    >
      {label || children}
    </button>
  )
end

export default Button

component UserProfile do
  # 1. Regular Ruby variables
  user = {
    first_name: "Jane",
    last_name: "Doe",
    avatar_url: "https://placeholder.com/avatar.png",
    is_admin: true
  }

  # 2. A Ruby method, called from inside the markup
  def format_name(person)
    "#{person[:first_name]} #{person[:last_name]}"
  end

  # 3. Inline style hash (camelCase properties, just like React)
  alert_style = {
    color: "darkred",
    backgroundColor: "pink",
    padding: "10px",
    borderRadius: "5px"
  }

  return (
    # Rule: wrap multiple elements in a single root container (or an empty fragment <>)
    <>
      {/* Dynamic text injection using curly braces */}
      <h1>Welcome back, {format_name(user)}!</h1>

      {/* Dynamic attribute binding using curly braces (no quotes around braces) */}
      <img
        src={user[:avatar_url]}
        alt="User profile picture"
        className="profile-image" # Rule: use 'className' instead of 'class'
      />

      {/* Conditional rendering using a Ruby ternary */}
      {user[:is_admin] ? (
        <p style={alert_style}>Admin privileges active.</p>
      ) : (
        <p>Standard user account.</p>
      )}

      {/* Event handlers are JavaScript, so they are written as strings */}
      <button onClick={"alert('Settings opened!')"}>
        Account Settings
      </button>
    </>
  )
end

export default UserProfile

# A more involved component: loops, conditional branches, helper methods,
# computed classes and inline styles.

import Button from "components/button"

component UserTable do |users:, sort: :name, current_user: nil|
  # Plain Ruby methods, defined and called like JavaScript function declarations.
  def initials(user)
    user[:name].split.map { |part| part[0] }.join.upcase
  end

  def status_style(user)
    { color: user[:active] ? "#0a7" : "#999", fontWeight: user[:active] ? 600 : 400 }
  end

  sorted = users.sort_by { |user| user[sort].to_s }

  return (
    <table className="users">
      <thead>
        <tr>
          <th>Person</th>
          <th>Status</th>
          <th className="numeric">Posts</th>
          <th></th>
        </tr>
      </thead>

      <tbody>
        {sorted.map do |user|
          <tr
            key={user[:id]}
            className={{ "is-you" => user == current_user, "is-inactive" => !user[:active] }}
            data={{ user_id: user[:id] }}
          >
            <td>
              <span className="avatar">{initials(user)}</span>
              {user[:name]}
              {user == current_user && <em className="you"> (you)</em>}
            </td>

            <td style={status_style(user)}>
              {user[:active] ? "Active" : "Inactive"}
            </td>

            <td className="numeric">{user[:posts_count]}</td>

            <td>
              <Button label="Edit" variant="link" size="sm" data-user={user[:id]} />
            </td>
          </tr>
        end}
      </tbody>

      {users.empty? && (
        <tfoot>
          <tr><td colSpan={4}>Nobody here yet.</td></tr>
        </tfoot>
      )}
    </table>
  )
end

export default UserTable

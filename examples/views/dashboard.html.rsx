# A Rails view: app/views/pages/dashboard.html.rsx
#
# Inside a view, `self` is the Rails view context, so controller instance
# variables and every Rails helper are available directly.

import Card from "components/card"
import Sidebar from "components/sidebar"
import UserTable from "components/user_table"

<div className="dashboard">
  <Sidebar section="dashboard" unread={@unread_count} />

  <main>
    <h1>Team</h1>

    <Card title="Everyone" footer={<a href="/users/new">Invite someone</a>}>
      <UserTable users={@users} current_user={@current_user} sort={:name} />
    </Card>

    {@users.empty? && (
      <Card title="Getting started">
        <p>Invite a teammate to see them listed here.</p>
      </Card>
    )}
  </main>
</div>

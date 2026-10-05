module Ui
  # Users, administrators only (domain §13.3 M7).
  class UsersController < BaseController
    before_action :require_admin

    def index
      list_page(title: "Users", rows: Users.list,
                columns: [Column.of("Email", "email"), Column.of("Name", "full_name"),
                          Column.of("Role", ->(r) { r["is_admin"] ? "Administrator" : "User" }),
                          Column.of("Status", "is_active", kind: "active")],
                link: ->(r) { "/users/#{r['id']}" }, new: ["/users/new", "New user"])
    end

    def new
      fields = [Field.of("email", "Email", "email", required: true), Field.of("full_name", "Name", required: true),
                Field.of("password", "Password", "password", required: true, help: "At least 8 characters."),
                Field.of("is_admin", "Administrator", "bool")]
      crud_form(title: "New user", fields:, initial: {}, back: "/users", done: ->(_) { "/users" }) { Users.create(_1) }
    end

    def edit
      user_id = id
      record = Users.json(Users.get(user_id))
      fields = [Field.of("email", "Email", "email", required: true), Field.of("full_name", "Name", required: true),
                Field.of("is_active", "Active", "bool"), Field.of("is_admin", "Administrator", "bool")]
      below = helpers.tag.p(helpers.link_to("Reset this user's password", "/users/#{user_id}/password"))
      crud_form(title: "Edit user", fields:, initial: record, back: "/users", done: ->(_) { "/users" }, below:) do |b|
        Users.update(current_user, user_id, b)
      end
    end

    def password
      user_id = id
      record = Users.json(Users.get(user_id))
      fields = [Field.of("password", "New password", "password", required: true,
                         help: "At least 8 characters. Signs the user out everywhere.")]
      crud_form(title: "Reset password for #{record['email']}", fields:, initial: {}, back: "/users/#{user_id}",
                done: ->(_) { "/users/#{user_id}" }) { Users.set_password(user_id, _1) }
    end
  end
end

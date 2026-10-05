module Api
  # User administration, administrators only (spec/api.md §5.1).
  class UsersController < BaseController
    admin_only

    def index = ok(Users.list)
    def show = ok(Users.json(Users.get(id)))
    def create = created(id: Users.create(body))

    def update
      Users.update(current_user, id, body)
      no_content
    end

    def password
      Users.set_password(id, body)
      no_content
    end
  end
end

module Api
  # Login, logout, and the current user (spec/api.md §3).
  class AuthController < BaseController
    skip_before_action :authenticate, only: %i[login logout]

    def login
      email, password = body.str("email"), body.str("password")
      raise ApiError::BadRequest, "email and password are required" if email.blank? || password.blank?

      user = Auth.authenticate(email, password) or raise ApiError::Unauthorized, "invalid email or password"
      cookies[Auth::COOKIE] = Auth.cookie(request, Auth.start_session(user))
      ok Auth::CurrentUser.new(user.id, user.email, user.full_name, user.is_admin)
    end

    def logout
      Auth.end_session(cookies[Auth::COOKIE])
      cookies.delete(Auth::COOKIE, path: "/", same_site: :lax)
      no_content
    end

    def me = ok(current_user)
  end
end

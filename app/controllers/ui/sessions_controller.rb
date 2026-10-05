module Ui
  # Sign-in and sign-out (domain §13 G1, G2).
  class SessionsController < BaseController
    skip_before_action :require_login

    def new
      return redirect_to(safe_next) if current_user

      login_page
    end

    def create
      email = params[:email].to_s
      user = email.strip.empty? ? nil : Auth.authenticate(email, params[:password].to_s)
      return login_page(error: "Invalid email or password.", email:) if user.nil?

      cookies[Auth::COOKIE] = Auth.cookie(request, Auth.start_session(user))
      redirect_to safe_next
    end

    def destroy
      Auth.end_session(cookies[Auth::COOKIE])
      cookies.delete(Auth::COOKIE, path: "/", same_site: :lax)
      redirect_to login_path
    end

    private

    def login_page(error: nil, email: "")
      page "ui/login", title: "Sign in", error:, email:, next_path: params[:next].to_s,
                       status: error ? :unauthorized : :ok
    end

    # Only a path on this site, never another host.
    def safe_next
      target = params[:next].to_s
      target.start_with?("/") && !target.start_with?("//") && !target.include?("\\") ? target : "/"
    end
  end
end

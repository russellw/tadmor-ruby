module Ui
  # The server-rendered UI's shared machinery (domain §13).
  #
  # UI actions call the same services as the JSON API, so the rules and the
  # error messages are the API's. Forms post plain HTML fields, which are
  # turned into the API's request-body shape (a Body) before the service sees
  # them. A failed action re-renders its page with the server's message next
  # to the action (G5); a successful one redirects.
  #
  # The UI shares the API's login session. Every form carries a token derived
  # from that session's secret token, checked on each POST, which stands in
  # for Rails' session-backed CSRF protection.
  class BaseController < ActionController::Base
    layout "application"

    before_action :load_user
    before_action :require_login
    before_action :verify_form_token, if: -> { request.post? }
    helper_method :current_user, :form_token

    rescue_from ApiError::NotFound, ApiError::BadRequest, with: :not_found
    rescue_from ApiError::Forbidden, with: :forbidden

    # G8: an unknown address.
    def not_found(_error = nil)
      @title = "Not found"
      render "ui/message", status: :not_found, locals: { message: "There is nothing at this address." }
    end

    private

    attr_reader :current_user

    def load_user = @current_user = Auth.session_user(cookies[Auth::COOKIE])

    def require_login
      redirect_to login_path(next: request.fullpath) if current_user.nil?
    end

    def require_admin
      raise ApiError::Forbidden, "administrators only" unless current_user.is_admin
    end

    def forbidden(_error = nil)
      @title = "Administrators only"
      render "ui/message", status: :forbidden, locals: { message: "This page is for administrators." }
    end

    def form_token
      token = cookies[Auth::COOKIE].to_s
      OpenSSL::HMAC.hexdigest("SHA256", token, "tadmor form")
    end

    def verify_form_token
      return if current_user.nil? # sign-in, which has no session yet; SameSite=Lax covers it
      return if ActiveSupport::SecurityUtils.secure_compare(params[:form_token].to_s, form_token)

      @title = "Form expired"
      render "ui/message", status: :forbidden,
                           locals: { message: "That form came from an old or another session. Go back, reload, and try again." }
    end

    # Run a service call in one transaction: [result, nil] on success,
    # [nil, message] on refusal, with nothing written.
    def attempt
      result = nil
      ActiveRecord::Base.transaction { result = yield }
      [result, nil]
    rescue ApiError => e
      raise if e.is_a?(ApiError::NotFound)

      [nil, e.message]
    rescue ActiveRecord::StatementInvalid => e
      mapped = ApiError.from_database(e) or raise
      [nil, mapped.message]
    end

    def page(template, title:, status: :ok, **locals)
      @title = title
      render template, status:, locals:
    end

    # GET shows the form; POST saves through the service or shows its refusal.
    def crud_form(title:, fields:, initial:, back:, done:, editing: false, readonly: false, notice: nil, below: nil)
      form = Form.new(fields, initial, editing:)
      error = nil
      if request.post? && !readonly
        result, error = attempt { yield form.body(params) }
        return redirect_to(done.call(result)) if error.nil?

        form.redisplay(params)
      end
      page "ui/form", title:, form:, error:, back:, readonly:, notice:, below:
    end

    def list_page(title:, rows:, columns:, link:, new: nil, empty: "Nothing here yet.")
      page "ui/list", title:, rows:, columns:, link:, new:, empty:
    end

    # A POSTed action on a detail screen: redirect back on success, or show
    # the detail again with the refusal next to the action.
    def act(name, admin: false, &)
      return redirect_to(detail_path) unless request.post?
      return detail(name => "Only administrators can do this.") if admin && !current_user.is_admin

      _, error = attempt(&)
      error ? detail(name => error) : redirect_to(detail_path)
    end

    def id = Values.positive_int(params[:id])
  end
end

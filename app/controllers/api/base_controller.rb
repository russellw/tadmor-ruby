# The JSON API's plumbing (spec/api.md §1, §3): authentication, one
# transaction per request, request bodies, and error responses.
#
# Actions are thin shells over the services: decode the path and body, call
# the service, encode the result. Every refusal is an ApiError carrying its
# status, or a database error mapped by SQLSTATE, rendered as
# {"error": "..."}. The checks run in the spec's precedence: authentication
# (401), then administrator (403), then the request itself (400), then the
# service's own checks.
module Api
  class BaseController < ActionController::API
    include ActionController::Cookies

    # Bodies are read by Body, never by Rails' parameter parsing, so a
    # malformed body is a 400 from our own code, after authentication.
    wrap_parameters false

    before_action :authenticate
    around_action :in_transaction

    def not_found = render_error(404, "no such endpoint")

    private

    attr_reader :current_user

    def self.admin_only(**options) = before_action(:require_admin, **options)

    def authenticate
      @current_user = Auth.session_user(cookies[Auth::COOKIE])
      render_error(401, "authentication required") if @current_user.nil?
    end

    def require_admin
      render_error(403, "administrator only") unless current_user.is_admin
    end

    # Commit only on success. The schema's deferred constraint triggers fire
    # at commit, after the action has rendered, so a refusal there replaces
    # the response.
    def in_transaction
      ActiveRecord::Base.transaction { yield }
    rescue ApiError => e
      render_error(e.status, e.message)
    rescue ActiveRecord::StatementInvalid => e
      mapped = ApiError.from_database(e) or raise
      render_error(mapped.status, mapped.message)
    end

    def render_error(status, message)
      self.response_body = nil
      render json: { error: message }, status:
    end

    def body = @body ||= Body.parse(request.raw_post)

    def path_param(name) = request.path_parameters.fetch(name)

    def id = Values.positive_int(path_param(:id))

    def date_param(name)
      v = request.query_parameters[name].to_s
      v.empty? ? nil : Values.parse_date(v, name, error: ApiError::BadRequest)
    end

    def ok(data) = render(json: data)

    def created(data) = render(json: data, status: :created)

    def no_content = head(:no_content)
  end
end

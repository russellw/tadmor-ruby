# The probes, at the root and without authentication (spec/api.md §2).
class HealthController < ActionController::API
  def healthz = render(json: { status: "ok" })

  def readyz
    ActiveRecord::Base.connection.select_value("SELECT 1")
    render json: { status: "ready" }
  rescue StandardError
    render json: { status: "database unavailable" }, status: :service_unavailable
  end
end

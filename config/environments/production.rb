Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_tags = [:request_id]
  # Behind a TLS-terminating proxy, which sets X-Forwarded-Proto.
  config.assume_ssl = ENV["ASSUME_SSL"] == "1"
end

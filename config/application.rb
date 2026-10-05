require_relative "boot"

# Only the Rails frameworks this app uses (docs/stack.md): no Action Cable,
# Active Storage, Action Text, Action Mailbox, Action Mailer, or Active Job.
require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

require "securerandom"

module Tadmor
  class Application < Rails::Application
    config.load_defaults 8.1

    # Everything runs in UTC, the database sessions included (database.yml),
    # so "today" is the UTC date (spec/api.md §1.2).
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # The schema is tadmor's (db/migrations), applied by our own runner
    # (Migrations); Active Record's migrations and schema dumps are not used.
    config.active_record.migration_error = false
    config.active_record.dump_schema_after_migration = false
    config.active_record.schema_format = :sql
    # References are the schema's to enforce; a violation maps to 422.
    config.active_record.belongs_to_required_by_default = false

    # Sessions and CSRF protection are our own, over the shared sessions
    # table (Auth, Ui::BaseController), so Rails' cookie session is off.
    config.session_store :disabled
    config.middleware.delete ActionDispatch::Flash
    config.action_controller.default_protect_from_forgery = false

    # Nothing persistent is signed or encrypted with it.
    config.secret_key_base = ENV["SECRET_KEY_BASE"].presence || SecureRandom.hex(64)

    config.generators.system_tests = nil
    config.autoload_lib(ignore: %w[tasks])

    # Email is sent only when SMTP_ADDR (host:port) is set; otherwise the email
    # endpoints answer 501 (spec/api.md §5.11).
    config.x.smtp_addr = ENV["SMTP_ADDR"].to_s
    config.x.smtp_user = ENV["SMTP_USER"].to_s
    config.x.smtp_pass = ENV["SMTP_PASS"].to_s
    config.x.mail_from = ENV["MAIL_FROM"].to_s
  end
end

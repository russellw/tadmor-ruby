Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  # test/test_helper.rb builds the test database from the shared migrations.
  config.active_record.maintain_test_schema = false
end

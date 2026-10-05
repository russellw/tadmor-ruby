ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"

# The test database is built exactly as production's is: wiped, then the
# shared migrations (db/migrations) applied. Each test then runs in a
# transaction that rolls back, so the seed data stays as a fresh instance
# has it. Deferred constraint triggers fire only at a real commit, so those
# checks are left to the conformance suite.
Migrations.reset!
Migrations.apply

class ActiveSupport::TestCase
  self.use_transactional_tests = true
end

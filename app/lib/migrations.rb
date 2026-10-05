# The migration runner for the shared schema (spec/README.md).
#
# Every db/migrations/*.up.sql is applied in lexical order, each in its own
# transaction together with the schema_migrations row that records it. The
# files are tadmor's and are never edited here; Active Record's own
# migrations are not used for them.
module Migrations
  # Serialises concurrent runners.
  LOCK_KEY = 0x7AD0_0001

  module_function

  def apply
    files = Dir[Rails.root.join("db/migrations/*.up.sql")].sort
    raise "no *.up.sql migration files found in db/migrations" if files.empty?

    conn = ActiveRecord::Base.connection
    applied = []
    conn.execute("SELECT pg_advisory_lock(#{LOCK_KEY})")
    begin
      conn.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())
      SQL
      done = conn.select_values("SELECT version FROM schema_migrations").to_set
      files.each do |f|
        version = File.basename(f, ".up.sql")
        next if done.include?(version)

        conn.transaction do
          conn.execute(File.read(f))
          conn.exec_insert("INSERT INTO schema_migrations (version) VALUES ($1)", "migration", [version])
        end
        applied << version
      end
    ensure
      conn.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})")
    end
    applied.each { |v| Rails.logger.info("applied migration #{v}") }
    applied
  end

  # Drop and recreate the public schema of a throwaway database, creating the
  # database first if it is missing. Only names ending in _test or
  # _conformance may be wiped.
  def reset!
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    name = config.fetch(:database)
    unless name.end_with?("_test", "_conformance")
      raise ArgumentError, "refusing to wipe database #{name}: its name must end in _test or _conformance"
    end

    params = { host: config[:host], port: config[:port], user: config[:username], password: config[:password] }.compact
    PG.connect(**params, dbname: "postgres") do |admin|
      if admin.exec_params("SELECT 1 FROM pg_database WHERE datname = $1", [name]).ntuples.zero?
        admin.exec("CREATE DATABASE #{admin.quote_ident(name)}")
      end
    end
    ActiveRecord::Base.connection.execute("SET client_min_messages = warning; DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
    ActiveRecord::Base.connection.reconnect!
    name
  end
end

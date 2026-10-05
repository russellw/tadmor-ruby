# Puma, for development, the conformance suite, and production alike.
# HTTP_ADDR is host:port; PORT alone overrides the port. Read before Rails
# loads, so plain Ruby only.
host, _, port = ENV.fetch("HTTP_ADDR", "127.0.0.1:8080").rpartition(":")
port = ENV["PORT"] unless ENV["PORT"].to_s.empty?
host = "0.0.0.0" if host.empty?
bind "tcp://#{host}:#{port}"

threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads threads_count, threads_count
workers Integer(ENV.fetch("WEB_CONCURRENCY", 0))

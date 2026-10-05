# tadmor-ruby developer tasks.
#
# Everything runs against the gems committed in vendor/cache: `make install`
# builds them into vendor/bundle offline, and no target touches the network
# except vendor-update.
RUBY ?= ruby

# Connection strings. Override on the command line, e.g.
#   make run DATABASE_URL=postgres://user:pass@host:5432/db
DATABASE_URL ?= postgres://tadmor:tadmor@127.0.0.1:5432/tadmor_ruby
TEST_DATABASE_URL ?= postgres://tadmor:tadmor@127.0.0.1:5432/tadmor_ruby_test
CONFORMANCE_DATABASE_URL ?= postgres://tadmor:tadmor@127.0.0.1:5432/tadmor_ruby_conformance
HTTP_ADDR ?= 127.0.0.1:8080

.DEFAULT_GOAL := help
.PHONY: help install run serve migrate adduser test conformance check vendor-check vendor-update db

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*## "}{printf "  make %-14s %s\n", $$1, $$2}'

install: ## Build the vendored gems into vendor/bundle (offline; compiles native extensions)
	bundle install --local

run: migrate ## Migrate, then run the development server on HTTP_ADDR (reloads on change)
	DATABASE_URL='$(DATABASE_URL)' HTTP_ADDR='$(HTTP_ADDR)' RAILS_ENV=development bundle exec puma -C config/puma.rb

serve: migrate ## Migrate, then run the production server on HTTP_ADDR
	DATABASE_URL='$(DATABASE_URL)' HTTP_ADDR='$(HTTP_ADDR)' RAILS_ENV=production bundle exec puma -C config/puma.rb

migrate: ## Apply pending shared-schema migrations
	DATABASE_URL='$(DATABASE_URL)' bin/rails tadmor:migrate

adduser: ## Create or reset an administrator: make adduser EMAIL=... NAME=... (password on stdin)
	DATABASE_URL='$(DATABASE_URL)' bin/rails tadmor:adduser EMAIL="$(EMAIL)" NAME="$(NAME)"

test: ## Run the test suite (wipes the _test database)
	DATABASE_URL='$(TEST_DATABASE_URL)' bin/rails test $(ARGS)

conformance: ## Run tadmor's conformance suite against a fresh server (wipes the _conformance DB)
	DATABASE_URL='$(CONFORMANCE_DATABASE_URL)' tools/conformance.sh $(ARGS)

check: vendor-check ## Syntax-check every Ruby file and check the vendor tree
	@find app config lib test tools -name '*.rb' -print0 | xargs -0 -n1 $(RUBY) -wc >/dev/null

vendor-check: ## Verify vendor/cache and dependencies.json against Gemfile and Gemfile.lock (offline)
	$(RUBY) tools/vendor.rb check

vendor-update: ## Re-resolve dependencies under the 7-day cooldown and vendor them (network)
	$(RUBY) tools/vendor.rb update

db: ## Start a local Postgres 17 container (podman) for development
	podman run -d --name tadmor-ruby-pg -e POSTGRES_USER=tadmor -e POSTGRES_PASSWORD=tadmor \
		-e POSTGRES_DB=tadmor_ruby -p 127.0.0.1:5432:5432 docker.io/library/postgres:17

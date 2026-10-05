The goal of this project is to develop comprehensive business management software.
It is the Ruby counterpart of tadmor (~/tadmor): the same product, specified by
tadmor's spec/ and checked by its conformance/ suite, built on a different stack so
the two can be compared (see ~/tadmor/docs/counterpart-metrics.md).

Technology stack:
Postgres for the database, using the shared schema from tadmor's db/migrations.
Ruby 3.3 and Rails 8.1 for the back end, taken as its component gems (railties,
actionpack, actionview, activerecord), not the rails meta-gem. Puma serves it.
Server-rendered ERB templates for the user interface; no npm, no asset pipeline.
See docs/stack.md for the decision and its rationale.

Schema design:
The schema is shared with tadmor and is not ours to redesign. Active Record models map
onto the existing tables and views; Active Record migrations are not used for it.
Our own runner (app/lib/migrations.rb) applies db/migrations.

Dependencies:
Supply-chain conscious throughout; keep the third-party footprint small, pinned, and
reviewable in-repo. The only permitted gems are those in the Gemfile and the tree they
lock, as described in docs/stack.md. New gems need a conversation first. vendor/cache
holds every locked .gem, committed; nothing is fetched from rubygems.org at build or
run time. Gems are locked for the ruby platform only, so native extensions build from
source. Change dependencies only through `make vendor-update` (tools/vendor.rb), never
by running bundle update directly; commit Gemfile, Gemfile.lock, vendor/cache, and
dependencies.json together.

Working on it:
Business rules live in app/services/, shared by the JSON API (app/controllers/api/) and
the HTML UI (app/controllers/ui/). Never put a rule in a controller.
Services raise ApiError subclasses carrying the spec's HTTP status; refusals by the
schema are mapped by SQLSTATE (ApiError.from_database).
Money is BigDecimal end to end. Never divide to compute a percentage; multiply by
Values::PERCENT. Never let a Float near an amount.
API bodies are read with Body (app/lib/body.rb), never through Rails params.
The Content Security Policy forbids inline styles and scripts; use public/app.css and
public/app.js. UI forms must include form_token_field.
Payments have a column named "method"; read it with p.method or p[:method], and use
Object#method only with an argument (PaymentMethodColumn).
spec/, conformance/, and db/migrations/ are copies from tadmor (spec/UPSTREAM);
never edit them here. Re-export from tadmor with spec/export.sh.
Before committing, run `make check`, `make test`, and `make conformance`; all must pass.

Version control:
Commit directly to the default branch. Do not create feature branches.

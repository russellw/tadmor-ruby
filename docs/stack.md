# Stack

**Status:** adopted 2026-10-05.

## Decision

- **Back end:** Ruby on Rails 8.1, taken as its component gems
  (`railties`, `actionpack`, `actionview`, `activerecord`) rather than the
  `rails` meta-gem. It serves both the JSON API required by tadmor's
  `spec/api.md` and the user interface.
- **User interface:** server-rendered ERB templates. No SPA, no npm, no
  importmap, Propshaft, or Hotwire, and no asset pipeline: one stylesheet
  and one script are served from `public/`.
- **Database:** Postgres 17 with the shared schema from tadmor's
  `db/migrations/`, through Active Record and the `pg` gem.
- **Web server:** Puma, Rails' default, in development, in the conformance
  run, and in production.
- **Runtime:** Ruby 3.3 from the operating system's packages, with its
  RubyGems and Bundler (Ruby 3.3.8 and Bundler 2.6.7 on the Ubuntu 26.04
  development machine; the Debian 13 deployment box ships Ruby 3.3 too).

## Why Rails

Rails is what Ruby web applications are built with, so this counterpart
measures what mainstream Ruby costs. The choice of framework was made by
the project's owner for that reason. What was decided here is how much of
Rails to take.

Measured on 2026-10-05 (Rails 8.1.4, resolved for the `ruby` platform,
owners from the RubyGems API), each option with `pg`, `puma`, `net-smtp`,
and `csv`:

| Option | Gems | Owner accounts |
| ------ | ---: | -------------: |
| `rails` meta-gem | 69 | 83 |
| Component gems + Action Mailer | 60 | 76 |
| **Component gems (chosen)** | **52** | **72** |
| Roda + Sequel + Erubi (a lean alternative, for reference) | 16 | 24 |

The meta-gem brings Action Cable, Active Storage, Action Text, Action
Mailbox, and Active Job, and their trees (websocket-driver, marcel,
globalid, the Trix editor, and others). tadmor uses none of them. Loading
only the frameworks an app needs is a configuration Rails documents and
supports (`config/application.rb` requires each railtie by name), so
taking the components instead of the meta-gem is still Rails as Rails
intends it to be used. It saves 17 gems and 11 owner accounts.

Action Mailer was left out for the same reason. tadmor sends one kind of
message, a PDF attached to a short note, and building that MIME document
takes about 40 lines (`app/lib/mailer.rb`) over `net-smtp`, which Action
Mailer itself uses. Action Mailer would add itself, the `mail` gem, `mini_mime`,
`net-imap`, `net-pop`, `date`, Active Job, and `globalid`: 8 more gems and
4 more owner accounts.

What remains splits three ways among the 72 accounts:

- **The Rails core team**, 12 accounts. RubyGems lists every member of the
  team as an owner of each Rails gem, so one organization counts many
  times, as it would on npm.
- **The Ruby core team**, 20 accounts, behind the gems that ship with Ruby
  as default or bundled gems (`bigdecimal`, `json`, `erb`, `irb`, `rdoc`,
  `net-smtp`, `csv`, and so on). Rails requires newer versions than Ruby
  3.3 ships, or Bundler needs them declared, so they are locked and
  vendored like any other gem. They are the language's own maintainers.
- **About 40 independent maintainers** for the rest: Rack, Puma, nio4r,
  `pg`, nokogiri and loofah (behind Action View's HTML sanitizer),
  `concurrent-ruby`, `i18n`, `tzinfo`, `minitest`, and smaller ones.

None of it can be trimmed further without leaving Rails: `railties`
requires `irb` (and through it `rdoc` and `rbs`), `rackup`, and `thor`, and Action View requires the HTML
sanitizer and so nokogiri, whether or not the app calls them.

The lean alternative, Roda and Sequel (both from Jeremy Evans) with Erubi,
would be about a third of the tree. It was passed over because the point
of this counterpart is to measure the framework Ruby shops actually choose.

## Why server-rendered templates

As in the other counterparts: ERB is part of Action View, so a
server-rendered UI removes tadmor's npm tree entirely rather than
reproducing it. `spec/README.md` allows server-rendered pages; the JSON API
remains mandatory alongside them.

## Permitted packages

The gems in `Gemfile`, and exactly the transitive tree they require as
locked in `Gemfile.lock`, and nothing else without a conversation first.
In particular:

- **Not the `rails` meta-gem**, and none of the frameworks it adds.
- **None of `rails new`'s extras**: no `bootsnap`, `debug`, `web-console`,
  `brakeman`, `rubocop`, `kamal`, `thruster`, `solid_*`, `jbuilder`,
  `importmap-rails`, `propshaft`, `turbo-rails`, or `stimulus-rails`.
- **No `bcrypt`** for `has_secure_password`. Passwords are hashed with
  PBKDF2-HMAC-SHA256 at 600,000 iterations, as tadmor does, through Ruby's
  own OpenSSL binding.
- **No test framework beyond Minitest**, which Active Support already
  requires, and `rack-test`, which Action Pack already requires. Rails'
  integration tests run on them, so testing adds nothing to the tree.

## Supply-chain posture

- **Vendored and committed.** `vendor/cache/` holds every locked gem as
  the `.gem` file rubygems.org publishes, unmodified, so a clean clone
  installs with no network. `bundle install --local` (`make install`)
  builds them into `vendor/bundle/`, which is not committed.
- **Pinned and hashed.** The `Gemfile` pins each direct gem to an exact
  version, and `Gemfile.lock` records a sha256 for every gem
  (`CHECKSUMS`), which Bundler verifies on install. `tools/vendor.rb check`
  also verifies, offline, that `vendor/cache/` holds exactly the locked
  gems with those checksums.
- **Source only.** The lock names only the `ruby` platform
  (`.bundle/config` sets `force_ruby_platform`), so no precompiled binary
  gem is installed. Gems with native extensions are compiled from their
  published source. nokogiri builds the libxml2 and libxslt sources it
  bundles, through `mini_portile2`. `pg` links the operating system's
  libpq.
- **Install-time code runs.** This is unavoidable in Ruby: a gem with a C
  extension is built by running its own `extconf.rb` at install time.
  Eleven gems build one: `bigdecimal`, `erb`, `io-console`, `json`,
  `nio4r`, `nokogiri`, `pg`, `prism`, `puma`, `racc`, and `rbs`.
  nokogiri's build also runs `mini_portile2`. RubyGems has no equivalent
  of npm's `ignore-scripts`. The other gems run nothing when installed.
- **Cooldown.** No version published less than 7 days ago, as tadmor's
  pnpm policy does. Bundler has no such setting, so `tools/vendor.rb update`
  (standard library only) re-resolves, holding back each too-recent version
  Bundler picked with a `!=` constraint in a marked block of the `Gemfile`,
  until every locked version is old enough. A root pin that is too recent
  is an error. On 2026-10-05 the cooldown held back `rdoc` 8.1.0, and the
  root pins avoided `pg` 1.7.0 and `net-smtp` 0.5.2.
- **Dependency manifest.** `tools/vendor.rb manifest` (which `update` runs)
  writes `dependencies.json`, the manifest tadmor's `tools/measure.py`
  reads (tadmor's `docs/counterpart-metrics.md`): every locked gem, its
  category, and the owner accounts RubyGems lists for it. `check` verifies
  that it lists exactly the locked gems. Every gem is runtime. There is no
  build step, and the test tooling is already in the runtime tree.
- **Hermetic build.** Measured 2026-10-05 at commit `f43529e`: a clean
  `git clone` was installed with `bundle install --local` in a container
  with `--network=none`, holding only the toolchain (Ubuntu 26.04's `ruby`,
  `ruby-dev`, `ruby-bundler`, `build-essential`, `libpq-dev`, and
  `libyaml-dev`). It installed, and Rails, `pg`, and nokogiri loaded.
  Installing twice at the same path gave byte-identical native extensions
  (12 shared objects, each installed in two places). That is level 4 of tadmor's ladder for the installed
  deployable, with install-time code required.
- **Toolchain:** Ruby 3.3 with RubyGems and Bundler, a C compiler, and
  libpq's headers, all OS packages. On Ubuntu:
  `apt install ruby ruby-dev ruby-bundler build-essential libpq-dev libyaml-dev`.

## How the application uses Rails

- **No generator skeleton.** The app is the files Rails needs and no
  others: `config/application.rb` loads only the Active Record, Action
  Controller, Action View, and test railties. There are no credentials
  files and no `config/master.key`; nothing is signed or encrypted with
  `secret_key_base`.
- **Active Record over the shared schema.** One model per shared table and
  view (`app/models/`), with table and key names set where Rails'
  conventions differ. Active Record's migrations are not used for the
  schema: `Migrations` (`app/lib/migrations.rb`) applies `db/migrations/`
  in order and records them in `schema_migrations`, and
  `config.active_record.maintain_test_schema` is off. Generated columns
  are read-only, since Rails 8 knows them as virtual. References are left
  to the schema (`belongs_to_required_by_default = false`), so a bad one is
  the database's 422, not a validation message.
- **Business rules in `app/services/`**, as modules of functions over the
  models, raising `ApiError` with the HTTP status. The JSON API and the UI
  both call them. Invoices, bills, credit notes, orders, and payments share
  one code path, parameterized by a kind descriptor (`app/services/kinds.rb`).
  Reports are aggregate SQL over the shared tables and views. Database
  refusals (unique, foreign-key, check, and trigger violations) map to 409
  or 422 by SQLSTATE (`ApiError.from_database`).
- **Exact decimals with BigDecimal**, which Active Record already returns
  for `numeric` columns. Request values are rounded half away from zero to
  their stored scale on the way in, and tax is computed by multiplying by
  0.01, never by dividing.
- **The API** (`app/controllers/api/`) is `ActionController::API` with
  cookies added. Bodies are read by our own `Body`, never by Rails'
  parameter parsing, so authentication (401) comes before a malformed body
  (400), as the spec orders them. Each request runs in one transaction.
  The schema's deferred constraint triggers fire at commit, after the
  action has rendered, so a refusal there replaces the response.
- **Our own sessions**, as in tadmor: the shared `sessions` table holds the
  SHA-256 of a random token, for a fixed 30 days, and every request
  re-reads the user. Rails' cookie session store and its CSRF protection
  are turned off, since both need a session of Rails' own. Instead, every
  UI form carries a token that is an HMAC of the login session's token,
  checked on each POST (`Ui::BaseController`). Sign-in itself has no
  session to tie a token to; the cookie's `SameSite=Lax` covers it.
- **The UI** (`app/controllers/ui/`, `app/views/ui/`) is `ActionController::Base`
  with ERB templates over the same services. Forms post plain HTML fields,
  which `Ui::Form` turns into the API's request-body shape, so the UI shows
  exactly the API's rules and messages (domain §13 G5). Each action runs in
  one transaction (`attempt`).
- **One script and one stylesheet**, `public/app.js` and `public/app.css`,
  the same as tadmor-python's and tadmor-php's. The line-item editor
  previews totals with exact BigInt arithmetic, rounded as the server
  rounds. Rails' Content Security Policy is set to same-origin on every
  page, so templates use no inline styles or scripts.
- **PDFs by hand**, as tadmor does: `app/lib/pdf.rb` writes standard-14
  Helvetica pages with Zlib, and `app/services/printing.rb` lays out the
  shared document form. The font widths in `app/lib/pdf_metrics.rb` are
  copied from tadmor's generated table.
- **Commands** are Rake tasks: `bin/rails tadmor:migrate` applies the
  shared migrations, `tadmor:adduser` bootstraps an administrator (password
  on stdin), and `tadmor:resetdb` wipes a database whose name ends in
  `_test` or `_conformance`. The server does not migrate on start: `make run`
  and `make serve` migrate first.
- **Tests.** Rails integration tests (`test/ui_test.rb`) walk the UI
  checklist through the real middleware stack. `test/test_helper.rb` builds
  the test database from the shared migrations, and each test runs in a
  transaction that rolls back. The JSON API is covered by the conformance
  suite.

## Consequences for the shared schema

Nothing is added to it. Rails features that want tables of their own
(Active Record's `ar_internal_metadata`, its migrations, and the database
session and cache stores) are not used. Active Record's own
`schema_migrations` bookkeeping is never consulted, so the table tadmor's
runner keeps under that name does not conflict with it.

## What would make these choices worth revisiting

- **The measured numbers.** If Rails' tree dominates the comparison in a way
  that undermines it, a second Ruby counterpart on Roda and Sequel
  (`tadmor-ruby-roda`) is the natural follow-up.
- **Ruby 3.4 or later.** More of the standard library moves from default to
  bundled gems, so the Gemfile will need to name a few more of them (`csv`
  is already named for that reason). The tree's owners would not change.
- **A richer client.** If more than the line editor needs client-side
  behaviour, Hotwire (Turbo) is the Rails-native candidate to discuss. It
  is one gem plus a vendored script, without npm.

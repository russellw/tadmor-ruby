# tadmor-ruby

The Ruby counterpart of [tadmor](https://github.com/russellw/tadmor): the same
business management software, specified by tadmor's `spec/` and checked by its
`conformance/` suite, built on Ruby on Rails and Postgres so the stacks can be
compared. See [`docs/stack.md`](docs/stack.md) for the stack and its
supply-chain posture, and [`docs/ui-coverage.md`](docs/ui-coverage.md) for how
the UI meets the checklist of `spec/domain.md` §13.

## Layout

```
app/services/      business rules, shared by the JSON API and the UI
app/controllers/   api/ (the JSON API), ui/ (the server-rendered UI), health (probes)
app/views/ui/      ERB templates for the UI
app/models/        Active Record models over the shared tables and views
app/lib/           values and request bodies, errors, auth, migrations, PDF, mail, UI forms
config/            Rails configuration: application, routes, puma, database
public/            the UI's one stylesheet and one script
lib/tasks/         tadmor:migrate, tadmor:adduser, tadmor:resetdb
test/              Rails integration tests walking the UI checklist
tools/             vendor.rb (dependencies, dependencies.json), conformance.sh
vendor/cache/      every third-party gem, committed as published (tools/vendor.rb check)
spec/, conformance/, db/migrations/   copies from tadmor; never edited here
```

## Prerequisites

- **Ruby 3.3** with RubyGems and Bundler, a C compiler, and libpq's headers,
  from the OS. On Ubuntu: `apt install ruby ruby-dev ruby-bundler
  build-essential libpq-dev libyaml-dev`.
- **Postgres 17** reachable via `DATABASE_URL` (`make db` starts a container).
- **Go**, only to run the conformance suite.

## Build, run, test

`make install` builds the committed gems into `vendor/bundle/` offline,
compiling their native extensions (about a minute and a half). Run `make` to
list the other targets:

```sh
make run          # migrate, then serve the UI and API on HTTP_ADDR (default 127.0.0.1:8080)
make serve        # the same in production mode
make adduser EMAIL=you@example.com NAME='Your Name'   # password on stdin
make test         # Rails integration tests (wipes tadmor_ruby_test)
make conformance  # tadmor's suite against a fresh server (wipes tadmor_ruby_conformance)
make check        # syntax-check, and verify vendor/cache against Gemfile.lock offline
```

Override connection strings on the command line, e.g.
`make run DATABASE_URL=postgres://user:pass@host:5432/db`.

| Env var | Purpose |
| ------- | ------- |
| `DATABASE_URL` | Postgres connection string |
| `HTTP_ADDR`, `PORT` | Listen address (default `127.0.0.1:8080`); `PORT` alone overrides the port |
| `SMTP_ADDR`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` | Outbound email; without `SMTP_ADDR` the email endpoints answer 501 |
| `ASSUME_SSL` | `1` behind a TLS-terminating proxy |

## Dependencies

Rails' component gems, `pg`, `puma`, `net-smtp`, and `csv`, with their tree:
52 gems, pinned exactly with sha256 checksums and committed in `vendor/cache/`.
A clean clone installs offline. Change them only with `make vendor-update`,
which enforces a 7-day release cooldown and rewrites `dependencies.json`; see
[`docs/stack.md`](docs/stack.md).

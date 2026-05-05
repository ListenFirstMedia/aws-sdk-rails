# CLAUDE.md — `aws-sdk-rails` (LFM fork)

> **One-line purpose:** LFM's fork of the upstream `aws/aws-sdk-rails` Ruby gem, carrying a single one-line patch to `clear_active_connections!` for multi-DB Rails 7 compatibility.

## 1. Repo identity

- **Repo type:** `library` (Ruby gem; LFM fork of OSS upstream).
- **Primary language(s):** Ruby `>= 2.3` (per `aws-sdk-rails.gemspec` `required_ruby_version`).
- **Primary framework(s):** Ruby gem packaging; integrates with Rails (`railties >= 5.2.0`). The library provides Railtie-based plugins for ActionMailer (SES + SESv2), ActiveJob (SQS adapter, sync + async), Action Dispatch session (DynamoDB), Aws::Record (DynamoDB ORM), and AWS-SDK Rails-logger integration.
- **Lifecycle status:** `maintenance-only` — single LFM patch on top of upstream v3.9.0. Upstream is at https://github.com/aws/aws-sdk-rails (the Apache-2.0 project); LFM tracks it.
- **Repo URL:** https://github.com/ListenFirstMedia/aws-sdk-rails (default branch: `main`).
- **On-call / owners:** _<TODO: confirm — the only LFM commit is by `Anthony Battaglia <anthony.battaglia@listenfirstmedia.com>`, dated 2024-01-23. Anthony or the platform team probably owns it.>_
- **Slack channel:** _<TODO>_
- **Confluence / docs root:** Upstream README at https://github.com/aws/aws-sdk-rails (24 KB, vendored as `README.md` here). YARD docs (`yard` gem in `:docs` group).

## 2. Why this repo exists

LFM forked `aws/aws-sdk-rails` to apply one tiny Rails-7-multi-database compatibility fix: `clear_active_connections!` is called **without arguments** in `Aws::Rails::SqsActiveJob::JobRunner#clear_connections!`, so it defaults to the **current ActiveRecord role** rather than hardcoding a specific role. Upstream (as shipped at v3.9.0) was hardcoding the role, which broke LFM's read-replica/multi-DB SQS workers in `dsp` and `cms`.

The fork is consumed by:
- `cms` — via `gem 'aws-sdk-rails', git: 'git@github.com:ListenFirstMedia/aws-sdk-rails.git'`
- `dsp` — via `gem 'aws-sdk-rails', git: 'git@github.com:ListenFirstMedia/aws-sdk-rails.git', branch: 'main'` (in `dsp/api/Gemfile`)

There is no in-house code in this repo beyond that one patch — everything else is upstream Apache-2.0 source.

## 3. Where it sits in the platform

A pure Ruby library; no runtime services to call.

- **Upstream services this repo calls** (runtime HTTP/RPC): _N/A — this is a gem. At runtime, code that uses this gem will reach AWS APIs (SES, SQS, DynamoDB) via the bundled `aws-sdk-*` gems. The gem itself initiates no calls when loaded._
- **Downstream consumers** (LFM repos that bundle THIS as a gem):
  - `cms` — uses for ActionMailer SES delivery + SQS ActiveJob.
  - `dsp` — uses for SQS ActiveJob (the LFM patch is critical here — `dsp` is a heavy SQS worker).
- **Library deps** (compile-time, from `aws-sdk-rails.gemspec`):
  - `aws-record ~> 2`
  - `aws-sdk-ses ~> 1, >= 1.50.0`
  - `aws-sdk-sesv2 ~> 1, >= 1.34.0`
  - `aws-sdk-sqs ~> 1, >= 1.56.0`
  - `aws-sessionstore-dynamodb ~> 2`
  - `concurrent-ruby ~> 1`
  - `railties >= 5.2.0`
  - `rails` (development only)

> Phase 1 dependency map for this repo: `~/Documents/claude-github/phase1/aws-sdk-rails.json`.

## 4. HTTP / RPC interface

_N/A — this is a Ruby gem; it exposes no HTTP routes._

It does, via Railtie initializers, install:
- Two ActionMailer delivery methods (`:ses`, `:sesv2`) backed by `Aws::SES::Client` / `Aws::SESV2::Client`.
- Two ActiveJob queue adapters (`:amazon_sqs`, `:amazon_sqs_async`) backed by `Aws::SQS::Client`.
- A DynamoDB-backed Action Dispatch session store (`ActionDispatch::Session::DynamoDbStore`).
- A `RAILS_ENV/EBS-SQSD` middleware (`Aws::Rails::Middleware::EbsSqsActiveJobMiddleware`) for Elastic Beanstalk worker tier.
- Rake tasks: `dynamo_db:session_store:*` and `aws_record:migrate`.
- An executable `bin/aws_sqs_active_job` for running an SQS poller as a standalone process.

## 5. APIs this repo CONSUMES

This is a gem; AWS calls happen inside consumer apps using its provided clients/adapters. From the gemspec:

| Target service | Purpose | How it's configured | Failure mode |
|---|---|---|---|
| **AWS SES (v1 + v2)** | ActionMailer delivery (`:ses` / `:sesv2`) | `Aws.config[:credentials]` + standard AWS SDK config; `Aws::Rails.add_action_mailer_delivery_method(:ses, client_options)` to override | Standard `Aws::Errors::ServiceError` |
| **AWS SQS** | ActiveJob queue adapter | `config.active_job.queue_adapter = :amazon_sqs`; per-queue config in `config/aws_sqs_active_job.yml` (in consumer app) | Adapter raises; ActiveJob retries per its own config |
| **AWS DynamoDB** | Session store + `Aws::Record` integration | `config/dynamo_db_session_store.yml` (in consumer app) | Session lookup falls through to nil |
| **AWS APIs in general** | Logging passthrough | `Aws.config[:logger] = Rails.logger` (set by Railtie) | — |

## 6. Tech stack details

- **Runtime versions:**
  - Ruby `>= 2.3` (per gemspec). LFM's actual consumers are on Ruby 3.2.2.
  - Tests run on a CI matrix of Ruby 2.3/2.4/2.5/2.6/2.7/3.0/3.1/3.2 + jruby-9.{1,2,3,4} × Rails 5.2/6.0/6.1/7.0/main.
- **Package manager(s):** Bundler (`Gemfile`, `aws-sdk-rails.gemspec`). Multiple per-Rails-version Gemfiles in `gemfiles/` for the CI matrix.
- **Build/test commands:**
  - Install: `bundle install`
  - Test: `bundle exec rake test` (or `rake` — default is test). Runs `Rake::TestTask` over `test/**/*_test.rb`.
  - Lint: `bundle exec rubocop` (`.rubocop.yml` + `.rubocop_todo.yml`).
  - Docs: `bundle exec yard` (`.yardopts` configures output).
  - Sample app: `cd sample_app && bundle install && bundle exec rails s` (a working Rails 7 app that uses the gem via `path: '../'`).
- **Notable internal LFM gems / packages bundled here:** None. Pure upstream gemspec.
- **Why we forked:** **One patch.** Commit `fbab7a6` (2024-01-23, Anthony Battaglia) titled _"remove argument to clear_active_connections (let it default to the current role)"_. The patch lands in `lib/aws/rails/sqs_active_job/job_runner.rb` `clear_connections!` — calls `clear_active_connections!` (no args) so AR defaults to the current role rather than being pinned to `:writing`. This matters when the SQS worker is reading from a replica DB.
  - Note: looking at the current file content, both branches of the version-conditional already use no-argument calls (`::ActiveRecord::Base.connection_handler.clear_active_connections!` for AR 7.1+, `::ActiveRecord::Base.clear_active_connections!` for older). So the LFM patch is already in HEAD; the upstream bug-being-worked-around is whatever pre-patch version of these calls had a `:writing` argument.

## 7. Local development

### 7.1 Required services

- None for unit tests (`rake test` uses `test/dummy/` Rails dummy app + mocked AWS clients).
- For `sample_app/` integration testing: SQLite (default `db.sqlite3`).
- **AWS credentials** are needed for integration tests that actually hit AWS, but the standard test suite is mocked.

### 7.2 Required env vars

| Name | Purpose | Example value | Where it's set |
|---|---|---|---|
| `VERSION` | Override the gem version at build time (used by `Rakefile`) | `3.9.0` | `Rakefile` reads `ENV['VERSION'] || File.read('VERSION')` |
| (standard AWS SDK creds) | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_PROFILE` | per AWS conventions | resolved by `Aws.config` chain |
| (Rails-encrypted credentials) | `Rails.application.credentials.aws.{access_key_id,secret_access_key,session_token}` | optional; merged into `Aws.config` by `Aws::Rails.use_rails_encrypted_credentials` (`railtie.rb`) | `config/credentials.yml.enc` in consumer |

The library reads no LFM-specific env vars.

### 7.3 First-time setup

```
1. asdf install ruby 3.2.2  # or any supported version >= 2.3
2. cd aws-sdk-rails
3. bundle install
4. bundle exec rake test       # full upstream test suite
5. # to test against a specific Rails version:
   BUNDLE_GEMFILE=gemfiles/rails-7.0.gemfile bundle install
   BUNDLE_GEMFILE=gemfiles/rails-7.0.gemfile bundle exec rake test
6. # to play with the sample app:
   cd sample_app && bundle install && bundle exec rake db:setup && bundle exec rails s
```

## 8. Tests

- **How tests are organized:** Standard Rails plugin layout. Tests under `test/`:
  - `test/aws/rails/middleware/` — `EbsSqsActiveJobMiddleware`
  - `test/aws/rails/sqs_active_job/` — Executor / JobRunner / Poller / etc.
  - `test/active_job/queue_adapters/` — adapter integration
  - `test/action_dispatch/session/` — DynamoDB session store
  - `test/generators/aws_record/model/` — generator output
  - `test/generators/dynamo_db/session_store_migration/` — generator output
  - `test/tasks/dynamo_db/` — rake task
  - `test/dummy/` — minimal Rails dummy app used as the host
  - `test_helper.rb` (entry)
- **How to run a single test:** `bundle exec ruby -Itest test/aws/rails/sqs_active_job/job_runner_test.rb -n test_run_clears_connections`
- **CI green criteria:** `.github/workflows/ci.yml` runs Test on the full Ruby × Rails matrix. PRs against `main` must pass.
- **Coverage target / current %:** Not configured. _<TODO: confirm whether SimpleCov is wired up; not in Gemfile.>_
- **Mocks vs. real services:** Tests use mocked AWS clients (no live AWS calls).

## 9. Deployment

- **Where it deploys:** _N/A — this is a gem. It is not "deployed" in the EC2/Capistrano sense._
- **How a deploy happens:** Consumer apps (`cms`, `dsp`) reference this gem via `git:` URL in their `Gemfile`s. To roll out a new version, push a new commit to LFM's `main` branch, then bump the consumer's pin (or remove it to use HEAD).
- **Branching model:** `main` only. `tasks/release/` is a git submodule pointing at `aws/aws-sdk-ruby-release-tools` — used for the upstream's release process; LFM doesn't typically run a "release" of this fork.
- **Infra-as-code:** N/A.
- **Rollback:** Pin the consumer back to the previous SHA.
- **Health-check endpoint:** N/A.

## 10. Configuration & secrets

- **Secret store:** N/A for the gem itself. Consumer apps use Rails encrypted credentials (`config/credentials.yml.enc`) — `Aws::Rails.use_rails_encrypted_credentials` reads `Rails.application.credentials[:aws]` and merges only `:access_key_id`, `:secret_access_key`, `:session_token` into `Aws.config`.
- **How config is loaded at runtime:**
  - The Railtie's `aws-sdk-rails.initialize` initializer (in `lib/aws/rails/railtie.rb`) runs **before** `:load_config_initializers` and:
    1. Calls `Aws::Rails.use_rails_encrypted_credentials` (merges Rails creds into `Aws.config`).
    2. Calls `Aws::Rails.add_action_mailer_delivery_method` for both `:ses` and `:sesv2`.
    3. Calls `Aws::Rails.log_to_rails_logger` (`Aws.config[:logger] = Rails.logger`).
  - `aws-sdk-rails.insert_middleware` initializer adds the EBS SQSD middleware.
  - SQS active-job config: consumer's `config/aws_sqs_active_job.yml` (per-queue-name overrides).
- **Where to find example values:** `sample_app/config/aws_sqs_active_job.yml`, `sample_app/config/dynamo_db_session_store.yml`, `sample_app/config/credentials.yml.enc` (encrypted).
- **Feature flags:** N/A.

## 11. Data stores & state

- **DynamoDB** — used by `ActionDispatch::Session::DynamoDbStore` (HTTP session storage) and by `Aws::Record` (DynamoDB ORM). Tables are created via the rake task `dynamo_db:session_store:create_table` (or via `aws_record:migrate` for `Aws::Record` models). Configuration lives in `config/dynamo_db_session_store.yml`.
- **SQS** — used as the queue backend for `ActiveJob`. Three adapters: `amazon_sqs` (sync send), `amazon_sqs_async` (async send via `concurrent-ruby` thread pool).
- **In-process state:**
  - `Aws::Rails::SqsActiveJob::Executor` maintains a thread pool for the SQS poller (executable `bin/aws_sqs_active_job`).
  - `Aws::Rails::SqsActiveJob::Poller` long-polls SQS in a loop.
  - `Aws::Rails::SqsActiveJob::Deduplication` provides FIFO-queue dedup-id support (added in v3.9.0).

## 12. File / directory map

```
aws-sdk-rails/
├── README.md                          — upstream Apache-2.0 README (24 KB) — describes all features in detail
├── CLAUDE.md                          — this file
├── CHANGELOG.md                       — upstream release notes, latest is 3.9.0 (2023-09-28)
├── CODE_OF_CONDUCT.md, CONTRIBUTING.md, LICENSE.txt — upstream stock files
├── VERSION                            — `3.9.0`
├── Gemfile                            — minimal: gemspec + rubocop + bcrypt/rspec for tests + yard for docs + octokit for release
├── Rakefile                           — rake test (default) + rubocop
├── aws-sdk-rails.gemspec              — upstream gemspec; authors still "Amazon Web Services"; spec.homepage points at upstream
├── .rubocop.yml, .rubocop_todo.yml    — lint config
├── .yardopts                          — YARD config
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/ci.yml               — CI test matrix: Ruby 2.3-3.2 × Rails 5.2/6.0/6.1/7.0/main
├── .gitmodules                        — submodule: tasks/release → github.com/aws/aws-sdk-ruby-release-tools
├── bin/aws_sqs_active_job             — executable: SQS poller process
├── lib/
│   ├── aws-sdk-rails.rb               — entry point: requires all subfiles, exposes Aws::Rails::VERSION
│   ├── aws/rails/
│   │   ├── railtie.rb                 — Rails plugin glue (4 initializers)
│   │   ├── ses_mailer.rb              — ActionMailer SES v1 delivery
│   │   ├── sesv2_mailer.rb            — ActionMailer SES v2 delivery
│   │   ├── notifications.rb           — ActiveSupport instrumentation for AWS SDK
│   │   ├── middleware/
│   │   │   └── ebs_sqs_active_job_middleware.rb  — Rack middleware for EBS worker tier
│   │   └── sqs_active_job/
│   │       ├── configuration.rb       — config DSL
│   │       ├── deduplication.rb       — FIFO queue dedup-id helpers (added 3.9.0)
│   │       ├── executor.rb            — thread pool runner
│   │       ├── job_runner.rb          — ⚠️ contains the LFM patch (clear_active_connections!) — see §6
│   │       ├── lambda_handler.rb      — AWS Lambda integration
│   │       └── poller.rb              — long-polling SQS consumer
│   ├── action_dispatch/session/
│   │   └── dynamodb_store.rb          — ActionDispatch::Session::DynamoDbStore
│   ├── active_job/queue_adapters/
│   │   ├── amazon_sqs_adapter.rb      — sync ActiveJob → SQS adapter
│   │   └── amazon_sqs_async_adapter.rb — async (thread-pool) variant
│   ├── generators/
│   │   ├── aws_record/model/          — `rails g aws_record:model` generator
│   │   └── dynamo_db/session_store_migration/  — `rails g dynamo_db:session_store_migration`
│   └── tasks/
│       ├── aws_record/migrate.rake    — `rake aws_record:migrate`
│       └── dynamo_db/session_store.rake  — `rake dynamo_db:session_store:*`
├── gemfiles/                          — per-Rails-version Gemfiles for the CI matrix
│   ├── rails-5.2.gemfile, rails-6.0.gemfile, rails-6.1.gemfile, rails-7.0.gemfile, rails-main.gemfile
├── doc-src/                           — YARD doc source/templates
├── tasks/release/                     — git submodule (aws/aws-sdk-ruby-release-tools)
├── test/                              — Minitest tests
│   ├── test_helper.rb
│   ├── action_dispatch/session/, active_job/queue_adapters/, aws/rails/middleware/, aws/rails/sqs_active_job/
│   ├── generators/aws_record/model/, generators/dynamo_db/session_store_migration/
│   ├── tasks/dynamo_db/
│   ├── fixtures/{table_config,models}/
│   └── dummy/                         — minimal Rails 7 dummy app for hosting tests
└── sample_app/                        — full Rails 7 sample app demonstrating SQS + SES + DynamoDB sessions; pulls in this gem via `path: '../'`
```

Not a monorepo — single gem at root, with `sample_app/` and `test/dummy/` as auxiliary apps for integration/unit testing.

## 13. Conventions & gotchas

### ⚠️ Committed credentials

**No new committed credentials found in this deep read.** This repo is unusual among LFM's: no `ghp_*` GitHub PAT in the Gemfile, no `AKIA*` AWS keys in any environment file, no third-party OAuth secrets. The Gemfile uses only `https://rubygems.org`. The encrypted `sample_app/config/credentials.yml.enc` is intentionally encrypted (Rails standard) and not a leak.

**No update to `~/Documents/claude-github/phase1/SECURITY_FINDINGS.md` is required for this repo.**

### General conventions

- **This is a fork with one patch.** Treat it as a vendored dependency. Don't add LFM-specific business logic here — that belongs in `cms` or `dsp`. Bug fixes and small Rails-compatibility patches are fine; large features go upstream.
- **The patch is in `lib/aws/rails/sqs_active_job/job_runner.rb`** (`clear_connections!` → `clear_active_connections!` with no arg). When pulling new upstream, **re-apply this patch** if it gets dropped.
- **Upstream source of truth is `https://github.com/aws/aws-sdk-rails`.** When fixing a bug, check upstream first — they may have already fixed it.
- **The gemspec authors and email remain `Amazon Web Services` / `aws-dr-rubygems@amazon.com`.** This is correct (Apache 2.0 attribution) — don't change to LFM.
- **`tasks/release/` is a git submodule** that points at AWS's release tooling. LFM doesn't typically use it (the fork is consumed via `git:` URL, not RubyGems). Don't run `rake release` unless you're publishing to RubyGems (which you almost certainly aren't).
- **CI matrix is heavy** — 12 Ruby versions × 5 Rails versions × the matrix exclusions. Pulling new upstream often means updating the matrix to drop dropped support.
- **No LFM consumer pins this gem to a SHA** explicitly; both `cms` and `dsp` use `git:` URL only with `branch:` (or default branch). Pushing to `main` here immediately exposes downstream consumers on their next `bundle install`.
- **`sample_app/` is a working Rails 7 app** demonstrating the gem's features end-to-end. Useful for reproducing issues without touching `cms`/`dsp`.

## 14. Common tasks (cookbook)

- **Run all tests:** `bundle exec rake test`
- **Run tests against a specific Rails version:** `BUNDLE_GEMFILE=gemfiles/rails-7.0.gemfile bundle install && BUNDLE_GEMFILE=gemfiles/rails-7.0.gemfile bundle exec rake test`
- **Run lint:** `bundle exec rubocop`
- **Run YARD docs:** `bundle exec yard`
- **Run the sample app:** `cd sample_app && bundle install && bundle exec rake db:setup && bundle exec rails s`
- **Sync from upstream** (when bumping upstream version): `git remote add upstream https://github.com/aws/aws-sdk-rails.git`, then `git fetch upstream`, then merge or cherry-pick + verify the LFM patch in `job_runner.rb` is preserved + push to `main`.
- **Bump the version** (consumed via git URL, so this is mostly cosmetic): edit `VERSION`, edit `CHANGELOG.md`, push.
- **Bump consumer pins after a fix:** push to `main` here, then in `cms` and `dsp`, run `bundle update aws-sdk-rails`. Verify SQS worker behavior on staging before deploying.

## 15. Known issues / migrations in flight

- **Single LFM patch (`fbab7a6`) on top of upstream v3.9.0.** When upstream releases v3.10+ (or whatever follows), the LFM merge needs to verify that `clear_active_connections!` no longer takes a hardcoded role argument; if so, the LFM patch can be dropped. If upstream re-introduces a role argument, the LFM patch must be re-applied.
- **Wide CI matrix.** Ruby 2.3 / 2.4 / 2.5 are EOL upstream. LFM doesn't run on those, but the matrix is still inherited from upstream. _<TODO: consider trimming the matrix in `.github/workflows/ci.yml` to just the Ruby + Rails combos LFM actually uses (3.2 + 7.0).>_
- **`rails-main.gemfile` matrix entry** tests against unreleased Rails. Sometimes flakes — known upstream issue.
- **No SimpleCov / coverage reporting.** Upstream doesn't ship it.
- **Upstream `aws/aws-sdk-rails` has continued development past v3.9.0** _<TODO: check if upstream is now at v3.10+ / v4.x and decide whether to merge.>_

## 16. Glossary

| Term | What it means here |
|---|---|
| `Aws::Rails` | The gem's Ruby module namespace. |
| `Aws::Rails::Railtie` | The Rails plugin entry point — wires up SES, SESv2, SQS, and middleware. |
| `Aws::Rails::SesMailer` / `Sesv2Mailer` | ActionMailer delivery method classes. |
| `Aws::Rails::SqsActiveJob::*` | Internals of the SQS-backed ActiveJob adapter (Configuration, Deduplication, Executor, JobRunner, LambdaHandler, Poller). |
| `Aws::Rails::Middleware::EbsSqsActiveJobMiddleware` | Rack middleware that intercepts SQS-daemon requests on Elastic Beanstalk worker tiers and dispatches them as ActiveJob runs. |
| `ActionDispatch::Session::DynamoDbStore` | Rails session store backed by DynamoDB. |
| `Aws::Record` | An Apache-2.0 LFM-unrelated DynamoDB ORM (separate gem; this repo provides Rails generators for it). |

## 17. AI agent guidance (do's and don'ts)

**Do:**

- Treat this repo as a **vendored fork**. Stay close to upstream.
- When pulling a new upstream version, **verify** that the `clear_active_connections!` no-arg patch is preserved in `lib/aws/rails/sqs_active_job/job_runner.rb`. If upstream changed the calling convention (e.g., back to `clear_active_connections!(:writing)`), re-apply the patch and document the reason.
- Run the full `rake test` matrix before pushing to `main` — consumers (`cms`, `dsp`) auto-pull on next `bundle install`.
- When fixing a real bug, **also open a PR upstream** at `aws/aws-sdk-rails`. The fork is meant to stay tiny.
- Mirror upstream coding style (RuboCop config + `.rubocop_todo.yml`).

**Don't:**

- Don't add LFM-specific business logic. That belongs in the consumer apps.
- Don't change the `gemspec` authors/email/homepage — they correctly attribute upstream.
- Don't push directly to `main` without running CI locally first; CI hits `main` on push and can break consumers immediately.
- Don't run `rake release` unless you're publishing to RubyGems (LFM consumes via `git:` URL).
- Don't initialize the `tasks/release/` git submodule unless you understand AWS's release tooling.
- Don't add credentials to `sample_app/config/credentials.yml.enc` and commit the master key — Rails encrypts the file, but the master key (typically `config/master.key` or `RAILS_MASTER_KEY` env var) must NEVER be committed.

## 18. Drift markers

- **Last verified against code:** 2026-04-30 by `Claude` (Phase 2 deep read).
- **What I read in full:**
  - Repo root: `README.md` (head, 50 lines), `CHANGELOG.md` (head), `aws-sdk-rails.gemspec` (full), `Gemfile` (full), `Rakefile` (full), `VERSION`, `.gitmodules`, `.github/workflows/ci.yml` (head)
  - `lib/aws-sdk-rails.rb` (full), `lib/aws/rails/railtie.rb` (head), `lib/aws/rails/sqs_active_job/job_runner.rb` (full)
  - Full directory listings of `lib/`, `lib/aws/rails/`, `lib/aws/rails/sqs_active_job/`, `gemfiles/`, `test/`, `sample_app/`, `.github/`
  - `git log` (HEAD = `fbab7a6`, the LFM patch commit)
- **What I did NOT read in full:**
  - 24 KB upstream `README.md` past the head (it's standard Apache-2.0 upstream docs).
  - All 151 `.rb` test files in `test/` and `sample_app/test/`.
  - Most `lib/aws/rails/sqs_active_job/*.rb` bodies (only `job_runner.rb` deep-read because of the LFM patch; others are upstream-as-is).
  - `lib/generators/*` template bodies.
  - All `sample_app/` source (it's a generated Rails 7 app for demo purposes).
  - `doc-src/templates/`.
- **Sections most likely to drift first:** §6 (when upstream releases v3.10+), §15 (the LFM patch's relevance vs. upstream).
- **Auto-checks (when wired up):**
  - [ ] `bundle exec rubocop` clean
  - [ ] `bundle exec rake test` green on the supported matrix
  - [ ] LFM patch in `lib/aws/rails/sqs_active_job/job_runner.rb` (`clear_active_connections!` no-arg) is still present after any merge
  - [ ] no committed credentials in tracked files

---

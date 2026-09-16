# miniloader

A small local upload service for the Nucbox: other services on the machine
(Hermes, a future podcast-maker/print-service, ...) POST a file to miniloader,
and it uploads it to a Backblaze B2 bucket and hands back the permanent URL.

Callers never see the B2 credentials — only miniloader holds them, and each
caller gets its own bearer token so miniloader can apply per-caller rate
limits and byte quotas.

## Why

Hermes (or any agent) can misfire and trigger a burst of uploads. miniloader
sits between agents and B2 so that:

- B2 application keys live in exactly one place (this service's `.env`).
- Every caller is rate-limited, concurrency-limited, and byte-quota-limited,
  independent of what the calling service does.
- Only files with an allowed extension/size make it to B2.

## Requirements

- Ruby >= 3.1 (this repo pins `3.3.6` via `.ruby-version`; see "Ruby via
  rbenv" below for installing it on a fresh machine)
- A Backblaze B2 bucket + an application key scoped to it (S3-compatible API)

## Ruby via rbenv

On a fresh Nucbox, install Ruby with a system-wide rbenv rather than the
distro package, so every service on the box (this one, and future siblings
like a print-service) shares one place to manage Ruby versions:

```bash
sudo apt update
sudo apt install -y git build-essential libssl-dev libreadline-dev \
  zlib1g-dev libyaml-dev libsqlite3-dev

sudo git clone https://github.com/rbenv/rbenv.git /opt/rbenv
sudo git clone https://github.com/rbenv/ruby-build.git /opt/rbenv/plugins/ruby-build

# Make rbenv's shims/bin available to every user's shell.
sudo tee /etc/profile.d/rbenv.sh > /dev/null <<'EOF'
export RBENV_ROOT=/opt/rbenv
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
EOF
sudo chmod +x /etc/profile.d/rbenv.sh
source /etc/profile.d/rbenv.sh

# Let any user trigger a rehash (e.g. after installing a gem with binaries).
sudo chmod -R a+rX /opt/rbenv

sudo RBENV_ROOT=/opt/rbenv /opt/rbenv/bin/rbenv install 3.3.6
sudo RBENV_ROOT=/opt/rbenv /opt/rbenv/bin/rbenv global 3.3.6
sudo RBENV_ROOT=/opt/rbenv /opt/rbenv/bin/rbenv rehash
```

Note: `/etc/profile.d` only applies to login shells, not systemd services —
`deploy/miniloader.service.example` sets `PATH`/`RBENV_ROOT` explicitly for
that reason.

Verify:

```bash
ruby -v   # should print 3.3.6
```

## Setup

```
bundle install
cp .env.example .env
```

Edit `.env`:

- `B2_KEY_ID`, `B2_APPLICATION_KEY`, `B2_BUCKET`, `B2_ENDPOINT`, `B2_REGION`,
  `B2_PUBLIC_URL_BASE` — from the B2 console (Application Keys page, and the
  bucket's S3-compatible endpoint).
- `MINILOADER_TOKENS` — one `name:token` pair per calling service, e.g.
  `hermes:<random>,podcast_maker:<random>`. Generate tokens with:
  ```
  ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
  ```
- Guardrail defaults (`MINILOADER_MAX_UPLOAD_BYTES`,
  `MINILOADER_ALLOWED_EXTENSIONS`, `MINILOADER_RATE_LIMIT_PER_MINUTE`,
  `MINILOADER_MAX_CONCURRENT_UPLOADS(_PER_CALLER)`,
  `MINILOADER_DAILY_BYTE_QUOTA`, `MINILOADER_MONTHLY_BYTE_QUOTA`) are
  reasonable starting points — tune them to your bucket/plan.

**`.env` is gitignored and must never be committed.** This repo is public;
only `.env.example` (placeholder values) is tracked.

## Running locally

```
bundle exec puma -C config/puma.rb config.ru
```

By default this binds to `127.0.0.1:4567` (see `MINILOADER_BIND`/`MINILOADER_PORT`
in `.env`).

## API

All requests except `/health` require `Authorization: Bearer <token>` using
one of the tokens configured in `MINILOADER_TOKENS`.

### `POST /uploads`

Either a multipart form with a `file` field, or a JSON body `{"path": "..."}`
pointing at a file already on disk (only if `MINILOADER_LOCAL_PATH_ROOT` is
set — see below; disabled by default).

```
curl -X POST http://127.0.0.1:4567/uploads \
  -H "Authorization: Bearer $HERMES_TOKEN" \
  -F file=@episode.mp3
```

Response:

```json
{
  "url": "https://f004.backblazeb2.com/file/my-bucket/hermes/20250101120000-ab12cd34-episode.mp3",
  "key": "hermes/20250101120000-ab12cd34-episode.mp3",
  "size": 12345678,
  "sha256": "..."
}
```

On rejection you get a 4xx/429 with `{"error": "..."}` explaining which
guardrail tripped (bad extension, too large, rate limit, concurrency limit,
daily/monthly quota).

### `GET /health`

Returns `{"status": "ok"}`. No auth required; used for systemd/monitoring.

### Local-path uploads

If callers and miniloader share a filesystem (e.g. Hermes drops a file
locally before asking miniloader to upload it), set
`MINILOADER_LOCAL_PATH_ROOT` to a directory and POST
`{"path": "/that/dir/episode.mp3"}` instead of a multipart file — avoids
copying the file over HTTP a second time. Paths outside that directory are
rejected. Leave the variable unset to disable this entirely (multipart
upload still works).

## Guardrails

All limits are enforced per caller token:

- **Extension/size allowlist** (`MINILOADER_ALLOWED_EXTENSIONS`,
  `MINILOADER_MAX_UPLOAD_BYTES`) — checked before anything touches B2.
- **Rate limit** (`MINILOADER_RATE_LIMIT_PER_MINUTE`) — sliding 60s window,
  in-process.
- **Concurrency limit** (`MINILOADER_MAX_CONCURRENT_UPLOADS`,
  `MINILOADER_MAX_CONCURRENT_UPLOADS_PER_CALLER`) — caps simultaneous
  in-flight uploads globally and per caller.
- **Byte quota** (`MINILOADER_DAILY_BYTE_QUOTA`, `MINILOADER_MONTHLY_BYTE_QUOTA`)
  — rolling 24h/30d totals computed from the upload log in SQLite.

Every successful upload is logged to SQLite (`db/miniloader.sqlite3` by
default) with caller, filename, size, sha256, B2 key, URL, and timestamp —
this is both the quota source of truth and an audit trail.

## Deployment

See `deploy/miniloader.service.example` for a systemd unit. Run this (and
any future sibling service, e.g. a print-service) under its own dedicated
system user with its own `.env`, so a bug or compromise in one service can't
read another service's credentials.

With rbenv installed system-wide as above:

```bash
sudo useradd --system --home /opt/miniloader --create-home --shell /usr/sbin/nologin miniloader
sudo git clone https://github.com/speedracr/miniloader.git /opt/miniloader
sudo chown -R miniloader:miniloader /opt/miniloader

sudo -u miniloader -H env RBENV_ROOT=/opt/rbenv PATH="/opt/rbenv/shims:/opt/rbenv/bin:$PATH" \
  bash -c 'cd /opt/miniloader && bundle config set --local path vendor/bundle && \
           bundle install --deployment --without development test'
sudo RBENV_ROOT=/opt/rbenv /opt/rbenv/bin/rbenv rehash

sudo -u miniloader cp /opt/miniloader/.env.example /opt/miniloader/.env
sudo -u miniloader nano /opt/miniloader/.env   # fill in real values, see Setup above
sudo chmod 600 /opt/miniloader/.env

sudo cp /opt/miniloader/deploy/miniloader.service.example /etc/systemd/system/miniloader.service
sudo systemctl daemon-reload
sudo systemctl enable --now miniloader
sudo systemctl status miniloader
curl http://127.0.0.1:4567/health
```

## Tests

```
bundle exec rspec
```

Specs use an in-memory SQLite database and a fake uploader — no network or
real B2 credentials required.

# CLAUDE.md

This repo is sasaya's personal dev sandbox (dev box). The notes below cover what to keep in mind when working in it.

## Documentation tone

READMEs, notes, and inline prompt text in this repo are read by sasaya only — **colloquial Cantonese + emoji is fine**, no need to follow the global CLAUDE.md formal-writing / typography rules.

`CLAUDE.md` itself is the exception: it must be written in English.

Same for commit messages, code comments (when actually needed), and anything pushed externally — follow the global rules and use English / formal style.

## Submodule discipline

This repo has two submodules:

| Path | Remote | Purpose |
|---|---|---|
| `clickhouse/` | `git@github.com:storyn26383/golden-clickhouse.git` | ClickHouse service and config |
| `claude/` | `git@github.com:storyn26383/.claude.git` | sasaya's personal Claude settings, mounted into the workspace container as `/home/sandbox/.claude` |

- **Don't edit any file inside a submodule from this sandbox** (including ClickHouse XML config and Claude skills/commands/settings).
- To change ClickHouse / Claude settings, `cd <submodule>`, commit and push from there, then come back to the sandbox and update the submodule pointer.
- `claude/` goes dirty easily — claude-code inside the workspace container writes runtime state (`projects/`, `scheduled_tasks.json`, etc.) into the mount; those are handled by the `claude` submodule's own `.gitignore`. When you see dirty state, distinguish runtime artifacts (ignore) from real config edits (handle them).
- After mounting, `claude/` is exposed inside the container as `/home/sandbox/.claude`, not `claude` — the mount target name differs from the host path.
- Codex CLI runtime state is stored under `./.data/codex` and mounted as `/home/sandbox/.codex`; this is local state, not tracked config.

## Docker access is restricted

The Claude Code sandbox can't access the Docker socket (OrbStack / Docker Desktop alike). Therefore:

- `docker compose build`, `docker compose up`, `docker ps`, etc. **fail** inside a Claude session.
- The user has to run them in their own terminal, or you tell them what to run.
- Don't waste cycles retrying — just tell them to run it themselves.

## Compose include structure

- `docker-compose.yml` uses `include:` to pull in `clickhouse/docker-compose.yml` (the `golden-clickhouse` submodule).
- An explicit `env_file: .env` is set because the submodule's own `.env` is a broken symlink (`../api/.env`).
- ClickHouse XML config has `<host>clickhouse</host>` referring to the service name, not the container name — after `include:` the services share a network so it still resolves.
- The `clickhouse` / `clickhouse-testing` `ports:` brought in from the submodule are forcibly emptied with `ports: !override []` (host doesn't publish them) — this is intentional.
- Requires Compose **v2.24+** (uses the `!override` tag).

## Dev container design principles

- **Mounts `./.data/workspace` to `/home/sandbox/workspace`** as the default workspace (host IDE edits show up immediately in the container under `~/workspace` via SSH or `make shell`). `make init` pre-creates the directory so the Docker daemon doesn't create it as root and break sandbox writes. Add other mounts by editing `docker-compose.yml` directly.
- Base image is `phpswoole/swoole:5.1-php8.3` (Debian bookworm); don't suggest switching to Alpine — the alpine variant doesn't ship dev tooling and would need a lot of plumbing.
- WORKDIR is `/home/sandbox/workspace` (the sandbox user's `~/workspace`), aligned with the host bind-mount target — `make shell` / SSH lands you there naturally.
- Two identities exist inside the container:
  - **`sandbox`** — Build args `UID` / `GID` track the host (`HOST_UID` / `HOST_GID`, defaults 1000/1000), with NOPASSWD sudo. SSH login, project writes inside the mount, and `make shell` all use `sandbox`.
  - **`root`** — sshd as PID 1 must run as root (auth, port binding), so the image's `USER` stays root. `docker compose exec workspace bash` defaults to root too; for a sandbox shell, use `-u sandbox` (already wired into `make shell`).
- The container runs **sshd** (`CMD /usr/sbin/sshd -D -e`); the host maps `127.0.0.1:${SANDBOX_SSH_PORT}:22` to container port 22 so DBs are reachable from the host through SSH tunnels.
- SSH auth **only accepts pubkey** and **disallows root login** (`PermitRootLogin no` + `PasswordAuthentication no`); the host's `${SSH_PUBKEY:-${HOME}/.ssh/id_ed25519.pub}` is mounted as `/home/sandbox/.ssh/authorized_keys`. SSH always logs in as `sandbox` (`make ssh` / `make tunnel` are wired up).
- `git` user.name / user.email come from the host via `git config --get` in the Makefile, are passed to the Dockerfile as build args (`GIT_USER_NAME` / `GIT_USER_EMAIL`), and end up in `/home/sandbox/.gitconfig`. After updating the host config, `make build` syncs.
- GitHub CLI (`gh`) is installed from GitHub's official apt repository.
- Bun is installed system-wide (`BUN_INSTALL=/usr/local`), not under `/root/.bun`, so the sandbox user can use it.
- Codex CLI is installed with `npm install -g @openai/codex`. The `codex` shell alias intentionally adds `--dangerously-bypass-approvals-and-sandbox` because this dev box is already externally sandboxed by Docker.
- DB services (`mysql` / `redis` / `clickhouse` / `clickhouse-testing`) are **all unpublished to the host** — internal network only. To reach them from the host, run `make tunnel`. **Don't suggest publishing DB ports directly** — the user already runs their own DBs locally and ports would clash.

## `.env` / environment variables

- `.env.example` is the single source of truth — when an env key changes, update both `.env.example` and `.env`.
- Defaults are tuned for casual local use (`root` / `default`); don't suggest making them "production-grade".
- `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` are forwarded from `.env` into the workspace container's `environment:` block in `docker-compose.yml` for claude-code. **Don't suggest using OAuth flow** — this is intentionally designed around token + proxy URL, login isn't needed.
- `GH_TOKEN` is forwarded from `.env` into the workspace container for GitHub CLI. Prefer this non-interactive token path over `gh auth login`.
- Codex uses ChatGPT login, not API key env vars in this repo. `make init` creates `.data/codex/config.toml` with `cli_auth_credentials_store = "file"` so auth is cached in the mounted `CODEX_HOME`; use `codex login --device-auth` from inside the workspace container for first-time login.
- `SANDBOX_SSH_PORT` (host SSH port, default `2222`) and `SSH_PUBKEY` (source for `authorized_keys`, default `${HOME}/.ssh/id_ed25519.pub`) are resolved through compose's `${VAR:-default}` syntax.
- `HOST_UID` / `HOST_GID` are auto-injected by the Makefile via `id -u` / `id -g` and exported; they're not stored in `.env` and don't need to be set manually. **Only build / start through the Makefile** — calling `docker compose build` directly falls back to compose's default `1000/1000` and breaks ownership.

## Before committing

Before each commit, check whether `README.md` needs to follow. If the change touches:

- Structural descriptions (`Workspace` section, `結構` section, mount tables)
- Onboarding workflow (`make` commands, `.env` variables, SSH / tunnel usage)
- Caveats worth remembering (`提一提` section)

update `README.md` together in the same commit. If the change is unrelated to the README, just commit.

## Don't

- **Don't write Dockerfile health checks / multi-stage builds / production hardening** — this is a dev box, over-engineering is pointless.
- **Don't add backwards-compat shims** (e.g. PHP 8.2 fallback, Swoole 4.x compatibility) — one version is enough.
- **Don't change the ClickHouse port / service name unilaterally** — it would break host references hardcoded in the `clickhouse/` submodule's XML.

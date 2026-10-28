# CLAUDE.md

This repo is sasaya's personal dev sandbox (dev box). The notes below cover what to keep in mind when working in it.

## Documentation tone

READMEs, notes, and inline prompt text in this repo are read by sasaya only — **colloquial Cantonese + emoji is fine**, no need to follow the global CLAUDE.md formal-writing / typography rules.

`CLAUDE.md` itself is the exception: it must be written in English.

Same for commit messages, code comments (when actually needed), and anything pushed externally — follow the global rules and use English / formal style.

## Submodule discipline

This repo has four submodules:

| Path | Remote | Purpose |
|---|---|---|
| `clickhouse/` | `git@github.com:storyn26383/golden-clickhouse.git` | ClickHouse service and config |
| `claude/` | `git@github.com:storyn26383/.claude.git` | sasaya's personal Claude settings, mounted into the workspace container as `/home/sandbox/.claude` |
| `omp/` | `git@github.com:storyn26383/.omp.git` | sasaya's personal omp settings, mounted into the workspace container as `/home/sandbox/.omp` |
| `omp-session-gateway/` | `git@github.com:storyn26383/omp-session-gateway.git` | sasaya's fork of omp-session-gateway (Cloudflare Access mode), mounted into the workspace container as `/home/sandbox/omp-session-gateway` and run by supervisord |

- **Don't edit any file inside a submodule from this sandbox** (including ClickHouse XML config, Claude skills/commands/settings, omp config, and omp-session-gateway source).
- To change ClickHouse / Claude / omp / omp-session-gateway, `cd <submodule>`, commit and push from there, then come back to the sandbox and update the submodule pointer.
- `omp-session-gateway/` gets `node_modules/` and `apps/web/dist/` from `make init-omp-gateway`; both are ignored by the submodule's own `.gitignore`.
- `claude/` goes dirty easily — claude-code inside the workspace container writes runtime state (`projects/`, `scheduled_tasks.json`, etc.) into the mount; those are handled by the `claude` submodule's own `.gitignore`. When you see dirty state, distinguish runtime artifacts (ignore) from real config edits (handle them).
- `omp/` gets runtime state (sessions, logs, auth) written into `agent/` by omp inside the container; its own `agent/.gitignore` whitelists only `config.yml`, `mcp.json`, and `models.yml`.
- After mounting, `claude/` is exposed inside the container as `/home/sandbox/.claude`, not `claude` (same for `omp/` → `/home/sandbox/.omp`) — the mount target name differs from the host path.

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

- **Mounts `./.data/workspace` to `/home/sandbox/workspace`** as the default workspace (host IDE edits show up immediately in the container under `~/workspace` via `make shell`). `make init` pre-creates the directory so the Docker daemon doesn't create it as root and break sandbox writes. Add other mounts by editing `docker-compose.yml` directly.
- Base image is `phpswoole/swoole:6.2-php8.5` (Debian bookworm); don't suggest switching to Alpine — the alpine variant doesn't ship dev tooling and would need a lot of plumbing.
- WORKDIR is `/home/sandbox/workspace` (the sandbox user's `~/workspace`), aligned with the host bind-mount target — `make shell` lands you there naturally.
- Two identities exist inside the container:
  - **`sandbox`** — Build args `UID` / `GID` track the host (`HOST_UID` / `HOST_GID`, defaults 1000/1000), with NOPASSWD sudo. Project writes inside the mount and `make shell` both use `sandbox`.
  - **`root`** — the image's final user is root (base image default); sections that switch to `USER ${USERNAME}` switch back to `USER root` at their end. `docker compose exec workspace bash` defaults to root too; for a sandbox shell, use `-u sandbox` (already wired into `make shell`).
- PID 1 is the base image's `/entrypoint.sh` with `CMD ["sleep", "infinity"]`, which keeps the container alive (compose sets `tty: true` + `stdin_open: true`). Because a command is given, the entrypoint runs in TASK mode: it copies `/etc/supervisor/task.d/*.conf` into `conf.d` and starts supervisord in the background beside `sleep`. The only supervisord program is `omp-gateway` (`supervisor/omp-gateway.conf`, a copy of the submodule's example with `directory` pointed at the submodule mount — keep it in sync). Access is via `make shell` (`docker compose exec`), not SSH.
- `git` user.name / user.email come from the host via `git config --get` in the Makefile, are passed to the Dockerfile as build args (`GIT_USER_NAME` / `GIT_USER_EMAIL`), and end up in `/home/sandbox/.gitconfig`. After updating the host config, `make build` syncs.
- GitHub CLI (`gh`) is installed from GitHub's official apt repository.
- Bun is installed system-wide (`BUN_INSTALL=/usr/local`), not under `/root/.bun`, so the sandbox user can use it. omp is installed with `bun install -g @oh-my-pi/pi-coding-agent` in the same section (package manager over the `omp.sh/install` script).
- Go 1.26.5 is installed from the official archive under `/usr/local/go`; the Dockerfile selects amd64 or arm64 and verifies its SHA-256 checksum.
- protoc is installed from the GitHub release (version pinned, SHA-256 checked) because bookworm's `protobuf-compiler` is too old for openim-app.
- Rust (rustup) and Flutter are installed as the `sandbox` user under `/home/sandbox` (`~/.rustup`, `~/.cargo`, `~/flutter`, `~/.pub-cache`) because both write into their own install dirs at runtime. Versions and the Rust target list mirror openim-app's `.fvmrc` and `rust-toolchain.toml`; rustup auto-installs any listed target that is missing, so the image pre-installs them all. fvm is intentionally not installed (`fvm use` would rewrite the macOS-side `.fvm` symlink on the shared mount); `MELOS_SDK_PATH` points melos at `~/flutter` instead.
- DB services (`mysql` / `redis` / `clickhouse` / `clickhouse-testing`) are **all unpublished to the host** — internal network only, no host path by design. Reach them from inside the container via `make shell`, connecting by service name (`mysql -h mysql`, `redis-cli -h redis`, `curl http://clickhouse:8123`). **Don't suggest publishing DB ports directly** — the user already runs their own DBs locally and ports would clash.
- **The Dockerfile is organised by scope** — each tool/topic (system packages, sandbox user, Node, Bun, Go, rtk, PHP…) is one section that keeps its own `ARG` / `ENV` / `RUN` together, never scattered across the file. Every section is introduced by a banner divider comment (a `# ===…` line, the section name, then another `# ===…` line). Each `RUN` cleans up after itself where it makes sense (`rm -rf /var/lib/apt/lists/*`, `npm cache clean --force`, delete downloaded archives / `pecl` build leftovers). When adding anything new, put it in the matching section and follow the same pattern.

## `.env` / environment variables

- The workspace service loads the whole `.env` via `env_file: .env`, so every key reaches the container; adding a token only needs `.env.example` and `.env`, no compose edit.
- `.env.example` is the single source of truth — when an env key changes, update both `.env.example` and `.env`.
- Defaults are tuned for casual local use (`root` / `default`); don't suggest making them "production-grade".
- `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` are loaded from `.env` into the workspace container for claude-code. **Don't suggest using OAuth flow** — this is intentionally designed around token + proxy URL, login isn't needed.
- `GH_TOKEN` is forwarded from `.env` into the workspace container for GitHub CLI. Prefer this non-interactive token path over `gh auth login`.
- `AI_GATEWAY_API_KEY` is the key omp's `omp/agent/models.yml` gateway provider reads (`apiKey: AI_GATEWAY_API_KEY`); keep the name in sync with that file.
- `CLOUDFLARE_TUNNEL_TOKEN` is mapped to `TUNNEL_TOKEN` for the `cloudflared` service (a remotely-managed tunnel; the token already carries the tunnel ID). Routes are configured in the Cloudflare dashboard only — don't add a local `config.yml` or credentials JSON. `cloudflared` uses `network_mode: "service:workspace"` because omp-session-gateway refuses non-loopback peers, so route targets are `http://localhost:<port>` (the gateway is `http://localhost:4317`) and `cloudflared` must be recreated whenever `workspace` is. Don't route DB services.
- `TAILSCALE_AUTH_KEY` is mapped to `TS_AUTHKEY` for the `tailscale` service, which is for inbound tailnet access to workspace dev servers only (`http://sandbox:<port>`); Cloudflare stays the only entry to omp-session-gateway. It shares `network_mode: "service:workspace"` (recreate it whenever `workspace` is recreated) and runs in **kernel (TUN) mode** on purpose: tailnet traffic arrives from a `100.x` address, so only listeners bound to `0.0.0.0` are reachable and the gateway on `127.0.0.1:4317` stays invisible. Don't switch to userspace mode — its netstack dials `localhost`, exposing every loopback listener to the tailnet (the #98 exposure described in `omp-session-gateway/apps/gateway/src/tailnet.ts`). Don't switch to tagged OAuth keys or add `TS_SERVE_CONFIG`. Node state lives in `.data/tailscale` and `make reset` deliberately keeps it so the node identity survives.
- `OMP_GATEWAY_TEAM_DOMAIN` / `OMP_GATEWAY_AUDIENCE` / `OMP_GATEWAY_ORIGIN` / `OMP_GATEWAY_ALLOWED_LOGINS` (comma-separated) feed `supervisor/omp-session-gateway-config.jq`, which `make init-omp-gateway` renders into `.data/omp-gateway/config/omp-session-gateway/config.json`. `omp-gateway install` is not used because it also installs a systemd/launchd service, which the container lacks. The gateway rejects group- or world-accessible config/state paths, so `.data/omp-gateway` stays `700` and `config.json` `600`.
- `HOST_UID` / `HOST_GID` are auto-injected by the Makefile via `id -u` / `id -g` and exported; they're not stored in `.env` and don't need to be set manually. **Only build / start through the Makefile** — calling `docker compose build` directly falls back to compose's default `1000/1000` and breaks ownership.

## Before committing

Before each commit, check whether `README.md` needs to follow. If the change touches:

- Structural descriptions (`Workspace` section, `結構` section, mount tables)
- Onboarding workflow (`make` commands, `.env` variables, shell / DB access)
- Caveats worth remembering (`提一提` section)

update `README.md` together in the same commit. If the change is unrelated to the README, just commit.

## Don't

- **Don't write Dockerfile health checks / multi-stage builds / production hardening** — this is a dev box, over-engineering is pointless.
- **Don't add backwards-compat shims** (e.g. PHP 8.2 fallback, Swoole 4.x compatibility) — one version is enough.
- **Don't change the ClickHouse port / service name unilaterally** — it would break host references hardcoded in the `clickhouse/` submodule's XML.

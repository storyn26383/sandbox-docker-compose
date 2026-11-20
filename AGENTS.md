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
| `omp/` | `git@github.com:storyn26383/.omp.git` | sasaya's personal omp settings, mounted into the workspace container as `/home/sandbox/.omp` |

- **Don't edit any file inside a submodule from this sandbox** (including ClickHouse XML config and omp config).
- To change ClickHouse / omp, `cd <submodule>`, commit and push from there, then come back to the sandbox and update the submodule pointer.
- `omp/` gets runtime state (sessions, logs, auth) written into `agent/` by omp inside the container; its own `agent/.gitignore` whitelists only `config.yml`, `mcp.json`, and `models.yml`.
- After mounting, `omp/` is exposed inside the container as `/home/sandbox/.omp`, not `omp` — the mount target name differs from the host path.

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
- Base image is `phpswoole/swoole:6.3-php8.4` (Debian 13 trixie); don't suggest switching to Alpine — the alpine variant doesn't ship dev tooling and would need a lot of plumbing.
- WORKDIR is `/home/sandbox/workspace` (the sandbox user's `~/workspace`), aligned with the host bind-mount target — `make shell` lands you there naturally.
- Two identities exist inside the container:
  - **`sandbox`** — Build args `UID` / `GID` track the host (`HOST_UID` / `HOST_GID`, defaults 1000/1000), with NOPASSWD sudo. Project writes inside the mount and `make shell` both use `sandbox`.
  - **`root`** — the image's final user is root (base image default); sections that switch to `USER ${USERNAME}` switch back to `USER root` at their end. `docker compose exec workspace bash` defaults to root too; for a sandbox shell, use `-u sandbox` (already wired into `make shell`).
- PID 1 is the base image's `/entrypoint.sh` with `CMD ["sleep", "infinity"]`, which keeps the container alive (compose sets `tty: true` + `stdin_open: true`). Access is via `make shell` (`docker compose exec`), not SSH.
- omp in the container is started from a host herdr pane with `sandbox omp` (zsh function in the chezmoi source `dot_oh-my-zsh/custom/scripts/sandbox.zsh`). It maps the pane's cwd under `./workspace` to the container path (`docker exec -w`), reconnects with `omp --restore=<id>` after a container restart, and kills the pane's leftover omp first (a dead `docker exec` client leaves its process running). herdr itself is not installed in the container.
- `herdr-relay.ts` never forwards a resume command from the container, since herdr types it into a host shell; it builds `sandbox omp <id>` itself from a UUID-shaped `agent_session_id`, and writes each pane's latest id to `.data/sandbox-omp/<pane-id>` for `sandbox omp` to reconnect with.
- The workspace container's hostname is fixed to `sandbox` (`hostname:` in compose; otherwise it is the container id and changes on recreate). omp's `hostname` status segment, enabled in `omp/agent/config.yml`, uses it to tell a sandbox omp from the host's (`mini`).
- `git` user.name / user.email come from the host via `git config --get` in the Makefile, are passed to the Dockerfile as build args (`GIT_USER_NAME` / `GIT_USER_EMAIL`), and end up in `/home/sandbox/.gitconfig`. After updating the host config, `make build` syncs.
- GitHub CLI (`gh`) is installed from GitHub's official apt repository.
- Git is built from the kernel.org source tarball (version pinned, SHA-256 checked) into `/usr/local`, built with `NO_RUST` because cargo isn't on root's PATH at that stage. Debian's apt `git` is still installed as a dependency of `gh` but sits behind `/usr/local/bin/git` on `PATH`.
- Bun is installed system-wide (`BUN_INSTALL=/usr/local`), not under `/root/.bun`, so the sandbox user can use it. omp is installed with `bun install -g @oh-my-pi/pi-coding-agent@${OMP_VERSION}` (version pinned) in the same section (package manager over the `omp.sh/install` script).
- Go 1.26.5 is installed from the official archive in the `go` stage and copied to `/usr/local/go`; the stage selects amd64 or arm64 and verifies its SHA-256 checksum.
- protoc is installed from the GitHub release (version pinned, SHA-256 checked) in the `protoc` stage because Debian's `protobuf-compiler` is too old for openim-app; its binary and `include/` are copied into `/usr/local`.
- Rust (rustup) and Flutter are built as the `sandbox` user under `/home/sandbox` (`~/.rustup`, `~/.cargo`, `~/flutter`, `~/.pub-cache`) in the `rust` / `flutter` stages, both built on a shared `toolchain-user` stage with the same `UID` / `GID`, and copied in with `--chown`; both write into their own install dirs at runtime. Versions and the Rust target list mirror openim-app's `.fvmrc` and `rust-toolchain.toml`; rustup auto-installs any listed target that is missing, so the image pre-installs them all. fvm is intentionally not installed (`fvm use` would rewrite the macOS-side `.fvm` symlink on the shared mount); `MELOS_SDK_PATH` points melos at `~/flutter` instead.
- DB services (`mysql` / `redis` / `clickhouse` / `clickhouse-testing`) are **all unpublished to the host** — internal network only, no host path by design. Reach them from inside the container via `make shell`, connecting by service name (`mysql -h mysql`, `redis-cli -h redis`, `curl http://clickhouse:8123`). **Don't suggest publishing DB ports directly** — the user already runs their own DBs locally and ports would clash.
- **The Dockerfile is organised by scope** — each tool/topic (system packages, sandbox user, Node, Bun, Go, rtk, PHP…) is one section that keeps its own `ARG` / `ENV` / `RUN` together, never scattered across the file. Every section is introduced by a banner divider comment (a `# ===…` line, the section name, then another `# ===…` line). Each `RUN` cleans up after itself where it makes sense (`rm -rf /var/lib/apt/lists/*`, `npm cache clean --force`, delete downloaded archives / `pecl` build leftovers). When adding anything new, put it in the matching section and follow the same pattern.
- **Dockerfile layers are ordered for cache reuse** — the toolchains (Rust, Flutter, Go, protoc) are separate stages from `BASE_IMAGE`, so they build in parallel and apt or CLI changes in the main image don't rebuild them. The `workspace` stage runs rarely changed layers first (apt, git, PHP, sandbox user, toolchain copies in the order Rust → Flutter → Go → protoc) and frequently bumped ones last (git identity from `GIT_USER_*`, the release-binary CLIs, Node, then omp at the very end). Put new tools by how often they change, not alphabetically.

## `.env` / environment variables

- The workspace service loads the whole `.env` via `env_file: .env`, so every key reaches the container; adding a token only needs `.env.example` and `.env`, no compose edit.
- `.env.example` is the single source of truth — when an env key changes, update both `.env.example` and `.env`.
- Defaults are tuned for casual local use (`root` / `default`); don't suggest making them "production-grade".
- `GH_TOKEN` is forwarded from `.env` into the workspace container for GitHub CLI. Prefer this non-interactive token path over `gh auth login`.
- `FRONTEND_GATEWAY_API_KEY` / `BACKEND_GATEWAY_API_KEY` are the keys omp's `omp/agent/models.yml` `frontend-gateway` / `backend-gateway` providers read (`apiKey: …`); keep the names in sync with that file.
- `TAILSCALE_AUTH_KEY` is mapped to `TS_AUTHKEY` for the `tailscale` service, which is for inbound tailnet access to workspace dev servers only (`http://sandbox:<port>`). It shares `network_mode: "service:workspace"` (recreate it whenever `workspace` is recreated) and runs in **kernel (TUN) mode** on purpose: tailnet traffic arrives from a `100.x` address, so only listeners bound to `0.0.0.0` are reachable and `127.0.0.1` listeners stay invisible. Don't switch to userspace mode — its netstack dials `localhost`, exposing every loopback listener to the tailnet. Don't switch to tagged OAuth keys or add `TS_SERVE_CONFIG`. Node state lives in `.data/tailscale` and `make reset-db` deliberately keeps it so the node identity survives.
- `tailscale` keeps running but stays disconnected after losing the control plane, so `restart:` never fires. It has a healthcheck — `tailscale status --json` reporting `Self.Online: true` (control-plane long poll) — plus the label `autoheal=true`. The `autoheal` service (`willfarrell/autoheal`, docker socket mounted, `network_mode: none`) restarts unhealthy labelled containers, because Compose doesn't. This is deliberate: it's a recovery mechanism, not production hardening.
- `HOST_UID` / `HOST_GID` are auto-injected by the Makefile via `id -u` / `id -g` and exported; they're not stored in `.env` and don't need to be set manually. **Only build / start through the Makefile** — calling `docker compose build` directly falls back to compose's default `1000/1000` and breaks ownership.

## Before committing

Before each commit, check whether `README.md` needs to follow. If the change touches:

- Structural descriptions (`Workspace` section, `結構` section, mount tables)
- Onboarding workflow (`make` commands, `.env` variables, shell / DB access)
- Caveats worth remembering (`提一提` section)

update `README.md` together in the same commit. If the change is unrelated to the README, just commit.

## Don't

- **Don't write Dockerfile health checks / production hardening, and keep multi-stage builds to isolating heavy toolchains (Rust, Flutter, Go, protoc)** so apt or CLI changes don't rebuild them — this is a dev box, over-engineering is pointless.
- **Don't add backwards-compat shims** (e.g. PHP 8.2 fallback, Swoole 4.x compatibility) — one version is enough.
- **Don't change the ClickHouse port / service name unilaterally** — it would break host references hardcoded in the `clickhouse/` submodule's XML.

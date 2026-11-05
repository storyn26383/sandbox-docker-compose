# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse) 落到 `clickhouse/`，一齊跑，唔使重複維護。omp 設定（skills / commands / settings）就用 [`storyn26383/.omp`](https://github.com/storyn26383/.omp) submodule 落到 `omp/`，再 mount 入 workspace container 做 `/home/sandbox/.omp`。omp-session-gateway 用 [`storyn26383/omp-session-gateway`](https://github.com/storyn26383/omp-session-gateway) submodule 落到 `omp-session-gateway/`，mount 做 `/home/sandbox/omp-session-gateway`。

## 入面有咩 📦

**Dev container**（base：[`phpswoole/swoole:6.2-php8.5`](https://hub.docker.com/r/phpswoole/swoole)）

| 類別 | 有咩 |
|---|---|
| 🐘 程式語言 | PHP 8.5、Swoole 6.2、Go 1.26.5、Rust 1.89.0、Flutter 3.44.1、Bun、Node.js 22 |
| 🧩 PHP 擴充 | bcmath、gd、intl、pcntl、zip、decimal |
| 🤖 CLI | omp、openspec、rtk、gh、glab、sentry-cli、slack、cloudflared、jq、ripgrep、fzf、htop、direnv |
| 🦀 App 開發 | melos、flutter_rust_bridge_codegen、cargo-audit、protoc 26.1 |
| 📝 編輯器 | Neovim（`nvim`），`VISUAL` / `EDITOR` 預設用佢 |
| 🌐 瀏覽器 | chromium（headless） |
| 🔨 Build | composer、git 2.56.0（source build）、build-essential、clang、cmake、ninja、pkg-config |
| 🗄️ DB client | mysql、redis-cli |
| 🌐 網絡 | curl、wget、ping、dig、nc |

**DB services**（全部唔 expose 到 host，純內網）

| Service | Image | 容器內 port |
|---|---|---|
| `mysql` | `mysql:8.0` | 3306 |
| `redis` | `redis:7-alpine` | 6379 |
| `clickhouse` | `clickhouse/clickhouse-server:23.3` | 8123 / 9000 |
| `clickhouse-testing` | `clickhouse/clickhouse-server:23.3` | 8123 / 9000 |

由於 host 上面已經有自己嘅 MySQL / Redis / ClickHouse 喺度跑，sandbox 嘅 DB **全部唔 publish 到 host**，避免 port 撞。要連 DB 就 `make shell` 入 container 用 service name（下面 [連 DB](#連-db-) section 講）。

容器之間照常用 service name 通到，例如喺 workspace 容器內 `mysql -h mysql`、`redis-cli -h redis`、`curl http://clickhouse:8123`。

## 點樣開工 🚀

### 第一次 clone

```bash
git clone --recurse-submodules <呢個 repo 嘅 url>
cd sandbox-docker-compose
make init       # 拉 submodule、cp .env、mkdir workspace、build image
make start
```

### Clone 完先發現唔記得 `--recurse-submodules`

```bash
git submodule update --init --recursive
```

### `.env`

`make init` 會自動 `cp .env.example .env`，啲嘢全部係本地最 chill 嘅預設值（`default` / `root`），要改自己 edit 就得。

`HOST_UID` / `HOST_GID` 唔放 `.env`，由 Makefile 用 `id -u` / `id -g` 即時注入畀 build args，跟你本機 user 一樣。**所以 build / start 一定要透過 Makefile**，唔好直接 `docker compose build`。

## 平時點用 🎮

```bash
make build      # build workspace image（改完 Dockerfile 行呢句）
make start      # 起所有 service（連埋 host 上嘅 herdr relay）
make stop       # 全部停（連埋 herdr relay）
make restart    # 重啟
make shell      # docker exec 入 workspace container（pwd ~/workspace）
make logs       # tail 晒所有 log
make reset-db   # 一鍵清晒 DB data（ClickHouse / MySQL / Redis）
make init-omp-gateway  # 裝 / build omp-session-gateway、由 .env 生成 config、重啟 gateway
```

## Workspace 📂

預設已經有一個 workspace mount：

| Host | 容器 |
|---|---|
| `./workspace/` | `/home/sandbox/workspace`（即 `~/workspace`） |

`make init` 會幫你預先 `mkdir` 好個目錄。Host 上面用任何 IDE 直接 edit `./workspace/...`，容器內即時見到（`make shell` 入去就喺 `~/workspace`）。`./workspace/` 已經 `.gitignore`，唔會污染 repo。

因為 sandbox 用戶 UID/GID 跟住 host 一樣，permission 自動匹配，host 同容器寫嘅檔案兩邊都當係你本機 user 擁有。`git` 嘅 user.name / user.email 喺 `make build` 嗰陣由 Makefile 從 host `git config` 攞返，build 入 image，commit 即用即得。

💡 workspace container 用 `env_file: .env` load 成個 `.env`，所以 `.env` 入面每條 key 都會入 container，加新 token 唔使改 `docker-compose.yml`。

## omp 嘅認證 🔐

omp 有兩個 gateway provider，`omp/agent/models.yml` 分別寫明 `frontend-gateway` 用 `apiKey: FRONTEND_GATEWAY_API_KEY`、`backend-gateway` 用 `apiKey: BACKEND_GATEWAY_API_KEY`，喺 `.env` 寫入：

```env
FRONTEND_GATEWAY_API_KEY=你個 frontend gateway key
BACKEND_GATEWAY_API_KEY=你個 backend gateway key
```

`make start` 之後自動入 workspace container，`omp` 直接用。改咗 `models.yml` 個 key 名嘅話，`.env` / `.env.example` 要跟住改。

omp 開外置編輯器會用 Neovim；image 已經設定 `VISUAL=nvim` 同 `EDITOR=nvim`，唔使另外加 `.env`。現有容器要先 `make build` 再 `make start`，之後重新 `make shell` 入去開 omp。

## GitHub CLI 嘅認證 🔐

`gh` 用 `GH_TOKEN`。喺 `.env` 寫入：

```env
GH_TOKEN=你個 GitHub token
```

`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，`gh` 會直接讀呢個 token，唔使再行 `gh auth login`。

## GitLab CLI 嘅認證 🔐

`glab` 用 `GITLAB_TOKEN`。自架 / GitLab Dedicated 就再加 `GITLAB_HOST` 指住個 instance，唔寫預設行 `https://gitlab.com`。喺 `.env` 寫入：

```env
GITLAB_HOST=https://gitlab.example.com
GITLAB_TOKEN=你個 GitLab token
```

`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，唔使再行 `glab auth login`。

## Sentry CLI 嘅認證 🔐

`sentry-cli` 用 `SENTRY_AUTH_TOKEN`。喺 `.env` 寫入：

```env
SENTRY_AUTH_TOKEN=你個 Sentry token
```

`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，唔使再行 `sentry-cli login`。

⚠️ `sentry-cli` 預設會 load 當前目錄（同上層）嘅 `.env`，但唔會蓋過已經 export 咗嘅 env，所以 `SENTRY_AUTH_TOKEN` 唔會被 project 換走；不過冇 set 嘅 `SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_URL` 就會由 project 嘅 `.env` 補上，喺唔同 project 行 org / project 可能自動變咗。用 `sentry-cli info` 睇實際讀咗乜。

## Notion / ClickUp token 🔐

冇裝 Notion / ClickUp CLI，平時經 remote MCP server 讀。token 留畀 MCP 用唔到嗰陣直接 call API 做 fallback。喺 `.env` 寫入：

```env
NOTION_API_TOKEN=你個 Notion PAT
CLICKUP_TOKEN=pk_你個 ClickUp personal token
CLICKUP_WORKSPACE=你個 workspace ID
```

## Slack CLI 嘅認證 🔐

唔行 `slack login`（嗰個 token 冇得收窄 scope，可以 deploy / delete app），淨係用 `slack api` 配一個自己開、得 read scope 嘅 user token。喺 `.env` 寫入：

```env
SLACK_USER_TOKEN=xoxp-你個 Slack user token
```

`make start` 之後自動 forward 入 workspace container，`slack api conversations.history channel=C0123456` 之類直接用得。

**點開 read-only token 🔒** — 去 https://api.slack.com/apps 開個 app，**User Token Scopes 淨係加 read 嘢**（`channels:read`、`channels:history`、`groups:read`、`groups:history`、`im:read`、`im:history`、`mpim:read`、`mpim:history`、`users:read`、`search:read`），千祈唔好加 `chat:write` 呢類 write scope。Install 落 workspace 之後攞 `xoxp-` 開頭嗰條 token。呢層係 Slack server-side 硬擋，call write method 一律回 `missing_scope`。

⚠️ `slack api` 揀 token 嘅次序係 `--token` → `--app` → `SLACK_BOT_TOKEN` → `SLACK_USER_TOKEN`，即係如果有 `SLACK_BOT_TOKEN`，會蓋過呢條 read-only token。

## omp-session-gateway + Cloudflare Tunnel 🌐

主要用途係經 Cloudflare Tunnel + Access 由外面用 [omp-session-gateway](https://github.com/storyn26383/omp-session-gateway)（`cloudflare-access` mode，詳情睇 submodule 入面嘅 `docs/CLOUDFLARE_ACCESS.md`）。

- Gateway 由 workspace container 入面嘅 supervisord 跑（`supervisor/omp-gateway.conf` build 入 image），聽 `127.0.0.1:4317`。
- `cloudflared` 係獨立 service，用 `network_mode: "service:workspace"` 同 workspace 共用 network namespace，所以 tunnel 入嚟嘅流量對 gateway 嚟講係 loopback。
- Route 全部喺 Cloudflare 後台（Networking → Tunnels）設定，repo 唔放 `config.yml`。

### 第一次設定

1. Cloudflare Zero Trust 開一個 **self-hosted Access application**，hostname 例如 `omp.example.com`，policy 淨係放自己。抄低 **AUD tag**（64 個 hex 字元）同 team domain（`<team>.cloudflareaccess.com`）。
2. 開一條 Cloudflare Tunnel，public hostname `omp.example.com` 指去 `http://localhost:4317`。
3. 喺 `.env` 寫入：

   ```env
   CLOUDFLARE_TUNNEL_TOKEN=你個 tunnel token
   OMP_GATEWAY_TEAM_DOMAIN=你個 team.cloudflareaccess.com
   OMP_GATEWAY_AUDIENCE=你個 AUD tag
   OMP_GATEWAY_ORIGIN=https://omp.example.com
   OMP_GATEWAY_ALLOWED_LOGINS=you@example.com
   ```

   `OMP_GATEWAY_ALLOWED_LOGINS` 可以用逗號分隔多個 email。Tunnel token 已經包含 tunnel ID，唔使另外指定。
4. `make build && make start`，跟住 `make init-omp-gateway`。
5. 驗證：`make shell` 入去行

   ```bash
   cd ~/omp-session-gateway
   XDG_CONFIG_HOME=~/.omp-gateway/config XDG_STATE_HOME=~/.omp-gateway/state bun apps/gateway/src/cli.ts doctor
   ```

   睇 `accessKeysReachable` 同 `accessEnforced` 係咪 `true`（`serviceInstalled` / `serviceActive` 係 `false` 係正常，因為唔係 systemd）。

### 平時

- 改咗 `OMP_GATEWAY_*` 或者更新咗 submodule，再行一次 `make init-omp-gateway`。
- Gateway 嘅 config / state 喺 `.data/omp-gateway`（mount 做 `~/.omp-gateway`），必須係 `700`；gateway 唔接受 group / world 讀得到嘅路徑。
- 未行 `make init-omp-gateway` 之前，supervisord 會重試幾次起 gateway，之後停喺 `FATAL`，`make logs` 會見到錯誤，唔影響其他嘢。
- 第一次 `make start` 之前，`cloudflared` 如果未填 token 會不停重啟、報錯。
- `workspace` 一重建（例如 `make build` 後 `make start`），`cloudflared` 都要跟住重建先會加入新嘅 network namespace；`make start` / `make restart` 會一齊處理。
- `cloudflared` 斷咗線唔會自己死，只會一路重試，有時一直連唔返。所以加咗 healthcheck（`cloudflared tunnel ready`，冇 edge connection 就 unhealthy），由 `autoheal` service 自動 restart。Metrics 綁 `127.0.0.1:20241`，tailnet 見唔到。
- 其他 dev server 想開出去，一樣喺後台加 route 指去 `http://localhost:<port>`，記得加 Access 保護。DB 唔好開出去。
- Image 用 `latest`，要更新就行 `docker compose pull cloudflared` 再 `make start`。
- 睇狀態：`docker compose logs cloudflared` / `docker compose logs workspace`（gateway log 會出喺 workspace 度），或者後台睇 tunnel 係咪 Healthy。

## Tailscale 🔗

喺自己部 Mac / 手機經 tailnet 直接連 workspace 入面嘅 dev server，唔使逐個 port 去 Cloudflare 後台加 route。

- `tailscale` 係獨立 service，同 `cloudflared` 一樣用 `network_mode: "service:workspace"`，tailnet 上面個 node 叫 `sandbox`。
- 行 kernel（TUN）mode，所以 **dev server 要 bind `0.0.0.0`** 先連得到（例如 `vite --host`），淨係 bind `127.0.0.1` 嘅連唔到。Gateway（`127.0.0.1:4317`）因此喺 tailnet 見唔到，入口照舊淨係 Cloudflare。
- 唔好轉 userspace mode：會將所有 loopback listener 開晒畀 tailnet。

### 第一次設定

1. Tailscale admin console → Settings → Keys 開一條 auth key。
2. 喺 `.env` 寫入：

   ```env
   TAILSCALE_AUTH_KEY=tskey-auth-...
   ```

3. `make start`，`docker compose logs tailscale` 見到 `Startup complete` 就得。
4. 驗證：`make shell` 入去行 `python3 -m http.server 8000 --bind 0.0.0.0`，喺 Mac 開 `http://sandbox:8000`。

### 平時

- Node state 喺 `.data/tailscale`，`make reset-db` 唔會清；註冊咗之後 auth key 過期都冇所謂。想重新註冊就自己 `rm -rf .data/tailscale`，記得喺 admin console 刪走舊 node，唔係新嗰個會變 `sandbox-1`。
- `workspace` 一重建，`tailscale` 都要跟住重建；`make start` / `make restart` 會一齊處理。
- 同 `cloudflared` 一樣有 healthcheck：`tailscale status --json` 嘅 `Self.Online`（同 coordination server 有冇連住）唔係 `true` 就 unhealthy，`autoheal` 會 restart。
- Image 用 `latest`，要更新就行 `docker compose pull tailscale` 再 `make start`。
- 要 HTTPS（secure context）嘅話臨時喺 container 行 `tailscale serve`，唔寫入 compose。

## autoheal 🩹

Compose 唔會 restart unhealthy 嘅 container，所以加咗 [`willfarrell/autoheal`](https://github.com/willfarrell/docker-autoheal)：每 5 秒 check 一次，有 `autoheal=true` label 而又 unhealthy 嘅 container（而家係 `cloudflared` 同 `tailscale`）就 `docker restart`。Restart sidecar 順便會重新加入 workspace 而家嘅 network namespace。

- 佢 mount 咗 `/var/run/docker.sock`，即係等同 host root；dev box 接受到，`network_mode: none` 至少令佢冇網絡。
- 睇有冇 restart 過：`docker compose logs autoheal`，或者 `docker ps` 睇 sidecar 個 `(healthy)` / `(unhealthy)`。
- 如果 `workspace` 係被重建（container ID 變咗），restart sidecar 會失敗；嗰種情況照舊要 `make start`。

## herdr 🐑

喺 [herdr](https://herdr.dev) 入面 `make shell` 再開 `omp`，sidebar、通知同 Collie 都見到佢嘅 `working` / `blocked` / `idle`，名同 host 嘅一樣係 `omp`（分唔到係刻意，Collie 要真名先會用嗰個 agent 嘅畫面規則）。

點運作：

- herdr 喺 pane 只見到 `docker exec`，認唔到入面嘅 agent，所以由 agent 自己報狀態：`omp/agent/extensions/herdr-state.ts`（host 同 sandbox 共用，有 `HERDR_RELAY_ADDRESS` 就行 sandbox 模式）
- OrbStack 唔傳得 macOS 嘅 Unix socket 入容器，所以 `make start` 會喺 host 起 `herdr-relay.ts`（`127.0.0.1:47123`），容器經 `host.docker.internal` 連返去
- `docker-compose.yml` 幫 workspace 設定 `HERDR_RELAY_ADDRESS`（port 跟 Makefile 嘅 `HERDR_RELAY_PORT`）；`make shell` 再將 `HERDR_ENV` / `HERDR_PANE_ID` 傳入容器，因為呢兩個係你喺邊個 herdr pane 行 `make shell` 先知，喺 herdr 以外行就唔會有
- container 重開或者 agent crash 時，agent 嚟唔切報 release，而 herdr 自己睇唔到 container 入面，會一直當 agent 仲喺度。所以 relay 會記低轉發過嘅 agent（`.data/herdr-relay-agents.json`），收到 `HERDR_RELAY_CONTAINER`（Makefile 設做 `sandbox-workspace`）嘅 docker `die` event 就代佢哋 release；relay 啟動時如果發現 container 喺佢停咗嗰陣重開過，都會 release

⚠️ herdr socket 可以喺任何 pane 打字、喺 host 行 command，所以 relay 只放行 source 係 `sandbox:*`、agent 係 `omp` 嘅狀態報告，剷走 `resume_argv` 同 `agent_session_path`，其他 request 一律 `relay_rejected`。唔好改做直接轉發。

限制：

- sandbox 入面嘅 agent herdr 重啟後唔會自動 resume（係刻意嘅：`sandbox:*` session 只記 id，唔會喺 host 行 resume）
- Collie 要用 `~/Coding/Sasaya/herdr`（`dev-env` branch）build 出嚟嘅 herdr，先會記低 `sandbox:*` 嘅 session id；官方 herdr 只記 `herdr:*`。另外 `~/.config/collie/.env` 嘅 `COLLIE_PI_ROOT` 要包埋 `omp/agent/sessions`，Collie 先搵到 sandbox 嘅 transcript
- relay log 喺 `.data/herdr-relay.log`；relay 死咗就 `make stop && make start`

## 連 DB 🔌

Sandbox 嘅 DB 全部唔 publish 到 host，host 冇直接連入嚟嘅路徑（設計如此，避免同你本機 DB port 撞）。要連 DB 就 `make shell` 入 workspace container，用 service name 連：

```bash
make shell
# 入到 container 後（已經係 sandbox user）直接：
mysql -h mysql -uroot -proot
redis-cli -h redis
curl 'http://clickhouse:8123/?query=SELECT+1'
```

如果有需要做 root 嘢（裝 apt package、改 system config），喺 workspace shell 度行 `sudo` 就得（NOPASSWD 已經配好），或者 `docker compose exec workspace bash` 直接以 root 入去。

## 結構 🗂️

```
sandbox-docker-compose/
├── docker-compose.yml          # 主 compose（include 埋 clickhouse 個 submodule）
├── .env / .env.example         # ClickHouse / MySQL credentials + omp gateway / gh / glab / Sentry / Slack / Notion / ClickUp / Cloudflare Tunnel / Tailscale token + omp-session-gateway 設定
├── Makefile                    # 全部 make 指令
├── herdr-relay.ts              # make start 喺 host 起嘅 herdr relay，只放行 sandbox agent 狀態報告；container 停咗就代 agent release
├── Dockerfile                  # workspace 容器點 build
├── supervisor/                 # omp-session-gateway 嘅 supervisord program（build 入 image）+ 由 .env 生成 gateway config.json 嘅 jq template
├── workspace/                  # 你嘅 workspace bind mount（gitignore）
├── .data/                      # MySQL / Redis 資料 + omp-session-gateway config / state bind mount 落呢度（gitignore）
├── omp/                        # submodule，sasaya 個人 omp 設定，mount 入容器做 /home/sandbox/.omp
├── omp-session-gateway/        # submodule（storyn26383/omp-session-gateway），mount 入容器做 /home/sandbox/omp-session-gateway
└── clickhouse/                 # submodule（storyn26383/golden-clickhouse），ClickHouse 嘅嘢全部喺呢度
```

## 清 DB 重新嚟過 🧹

```bash
make reset-db
```

會做兩樣嘢：

1. `docker compose down` —— 停晒所有 service
2. `rm -rf clickhouse/docker/.data/clickhouse .data/mysql .data/redis` —— 清 ClickHouse / MySQL / Redis 資料（保留 `./workspace`、`.data/omp-gateway` 同 `.data/tailscale`）

跟住 `make start` 就係一套全新 DB；gateway config / state 唔受影響。

## 提一提 ⚠️

- 要 Docker Compose **v2.20+**（用到 `include:` 指令）。Docker Desktop / OrbStack 2023-10 之後都得。
- ClickHouse 嘅 XML config（servers / macros / zookeeper / cors / timezone）由 submodule 提供，唔好喺 sandbox 度改；要改就入 `clickhouse/` 嗰個 submodule（remote 係 `storyn26383/golden-clickhouse`）改完 push。
- Apple Silicon（M 系）行得通，全部 image / install script 都有 arm64 版。
- Rust / Flutter 裝喺 sandbox user 嘅 home（`~/.cargo`、`~/.rustup`、`~/flutter`），冇裝 fvm。`MELOS_SDK_PATH` 已經指住 `~/flutter`，直接 `melos bootstrap` 就得，唔好喺 container 行 `fvm use`。
- `make shell` 入去嘅 sandbox bash 預設 `umask 022`，新開 folder 係 `755`、新檔案係 `644`。現有 container 要 `make build` 再 `make start`，之後重新 `make shell`。

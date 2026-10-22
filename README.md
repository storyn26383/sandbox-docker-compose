# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse) 落到 `clickhouse/`，一齊跑，唔使重複維護。Claude 個人設定（skills / commands / settings）就用 [`storyn26383/.claude`](https://github.com/storyn26383/.claude) submodule 落到 `claude/`，再 mount 入 workspace container 做 `/home/sandbox/.claude`。omp 設定都係咁，用 [`storyn26383/.omp`](https://github.com/storyn26383/.omp) submodule 落到 `omp/`，mount 做 `/home/sandbox/.omp`。

## 入面有咩 📦

**Dev container**（base：[`phpswoole/swoole:6.2-php8.5`](https://hub.docker.com/r/phpswoole/swoole)）

| 類別 | 有咩 |
|---|---|
| 🐘 程式語言 | PHP 8.5、Swoole 6.2、Go 1.26.5、Rust 1.89.0、Flutter 3.44.1、Bun、Node.js 22 |
| 🧩 PHP 擴充 | bcmath、gd、intl、pcntl、zip、decimal |
| 🤖 CLI | claude-code、omp、openspec、ccusage、rtk、gh、glab、sentry-cli、slack、cloudflared、jq、ripgrep、fzf、htop、direnv |
| 🦀 App 開發 | melos、flutter_rust_bridge_codegen、cargo-audit、protoc 26.1 |
| 📝 編輯器 | Neovim（`nvim`），`VISUAL` / `EDITOR` 預設用佢 |
| 🌐 瀏覽器 | chromium（headless） |
| 🔨 Build | composer、git、build-essential、clang、cmake、ninja、pkg-config |
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
make start      # 起所有 service
make stop       # 全部停
make restart    # 重啟
make shell      # docker exec 入 workspace container（pwd ~/workspace）
make logs       # tail 晒所有 log
make reset      # 一鍵清晒（連 ClickHouse data 都冚）
```

## Workspace 📂

預設已經有一個 workspace mount：

| Host | 容器 |
|---|---|
| `./workspace/` | `/home/sandbox/workspace`（即 `~/workspace`） |

`make init` 會幫你預先 `mkdir` 好個目錄。Host 上面用任何 IDE 直接 edit `./workspace/...`，容器內即時見到（`make shell` 入去就喺 `~/workspace`）。`./workspace/` 已經 `.gitignore`，唔會污染 repo。

因為 sandbox 用戶 UID/GID 跟住 host 一樣，permission 自動匹配，host 同容器寫嘅檔案兩邊都當係你本機 user 擁有。`git` 嘅 user.name / user.email 喺 `make build` 嗰陣由 Makefile 從 host `git config` 攞返，build 入 image，commit 即用即得。

## Claude Code 嘅認證 🔐

唔行 OAuth flow，靠 env var 直接通：

```env
ANTHROPIC_AUTH_TOKEN=你個 token
ANTHROPIC_BASE_URL=你個 proxy / gateway URL
```

寫入 `.env`（已 gitignore），`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，`claude` 啟動時直接攞嚟用，唔使再 login。

💡 workspace container 用 `env_file: .env` load 成個 `.env`，所以 `.env` 入面每條 key 都會入 container，加新 token 唔使改 `docker-compose.yml`。

## omp 嘅認證 🔐

omp 嘅 gateway provider 喺 `omp/agent/models.yml` 寫明 `apiKey: AI_GATEWAY_API_KEY`，喺 `.env` 寫入：

```env
AI_GATEWAY_API_KEY=你個 gateway key
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
├── .env / .env.example         # ClickHouse / MySQL credentials + Claude / gh / glab / Sentry / Slack / Notion / ClickUp token
├── Makefile                    # 全部 make 指令
├── Dockerfile                  # workspace 容器點 build
├── workspace/                  # 你嘅 workspace bind mount（gitignore）
├── .data/                      # MySQL / Redis 資料 + Claude Code 狀態 bind mount 落呢度（gitignore）
├── claude/                     # submodule，sasaya 個人 Claude 設定，mount 入容器做 /home/sandbox/.claude
├── omp/                        # submodule，sasaya 個人 omp 設定，mount 入容器做 /home/sandbox/.omp
└── clickhouse/                 # submodule（storyn26383/golden-clickhouse），ClickHouse 嘅嘢全部喺呢度
```

## 想清乾淨重新嚟過 🧹

```bash
make reset
```

會做兩樣嘢：

1. `docker compose down` —— 停晒所有 service
2. `rm -rf clickhouse/docker/.data/clickhouse .data/mysql .data/redis` —— ClickHouse / MySQL / Redis 資料一齊清（保留 `./workspace`）

跟住 `make start` 就係全新一個。

## 提一提 ⚠️

- 要 Docker Compose **v2.20+**（用到 `include:` 指令）。Docker Desktop / OrbStack 2023-10 之後都得。
- ClickHouse 嘅 XML config（servers / macros / zookeeper / cors / timezone）由 submodule 提供，唔好喺 sandbox 度改；要改就入 `clickhouse/` 嗰個 submodule（remote 係 `storyn26383/golden-clickhouse`）改完 push。
- Apple Silicon（M 系）行得通，全部 image / install script 都有 arm64 版。
- Rust / Flutter 裝喺 sandbox user 嘅 home（`~/.cargo`、`~/.rustup`、`~/flutter`），冇裝 fvm。`MELOS_SDK_PATH` 已經指住 `~/flutter`，直接 `melos bootstrap` 就得，唔好喺 container 行 `fvm use`。

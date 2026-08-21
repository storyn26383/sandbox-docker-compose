# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse) 落到 `clickhouse/`，一齊跑，唔使重複維護。Claude 個人設定（skills / commands / settings）就用 [`storyn26383/.claude`](https://github.com/storyn26383/.claude) submodule 落到 `claude/`，再 mount 入 workspace container 做 `/home/sandbox/.claude`。

## 入面有咩 📦

**Dev container**（base：[`phpswoole/swoole:6.2-php8.4`](https://hub.docker.com/r/phpswoole/swoole)）

| 類別 | 有咩 |
|---|---|
| 🐘 程式語言 | PHP 8.4、Swoole 6.2、Go 1.26.5、Bun、Node.js 22 |
| 🧩 PHP 擴充 | bcmath、gd、intl、pcntl、zip、decimal |
| 🤖 CLI | claude-code、codex、openspec、ccusage、ntn（Notion，read-only）、rtk、gh、cloudflared、jq、ripgrep、fzf、htop、direnv |
| 🌐 瀏覽器 | chromium（headless） |
| 🔨 Build | composer、git、build-essential |
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

## GitHub CLI 嘅認證 🔐

`gh` 用 `GH_TOKEN`。喺 `.env` 寫入：

```env
GH_TOKEN=你個 GitHub token
```

`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，`gh` 會直接讀呢個 token，唔使再行 `gh auth login`。

## Notion CLI 嘅認證 🔐

Notion 官方 CLI 叫 `ntn`（唔係 `notion`）。喺 `.env` 寫入：

```env
NOTION_API_TOKEN=你個 Notion PAT
```

`make start` 之後自動 forward 入 workspace container，`ntn` 直接讀，唔使行 `ntn login`（container 冇 keychain，行 login flow 好煩）。

**呢個 sandbox 入面 `ntn` 係 read-only 嘅，兩層防護：**

1. **PAT capabilities（真正防線 🔒）** — 去 https://app.notion.com/developers/connections 開 PAT 嗰陣，capabilities **淨係剔 `Read content`**（想睇 comment 就加埋 `Read comments`），千祈唔好剔 `Update content` / `Insert content`。呢層係 Notion server-side 硬擋，client 點改都繞唔到。
2. **Shell function（防手誤 ⚠️）** — container 內 `ntn` 被 `.bashrc` 一個 function 包住，只放行 read 命令（`api` GET、`pages get`、`datasources query/resolve`、`files get/list`、`doctor`），見到 `-X`、`--data` 或者任何 `key=value` inline body field 就即刻擋。**呢層淨係防手誤**，`command ntn` 一句就繞得過，所以第 1 點先係重點。

仲有，Notion 側要手動 share 目標 page / database 畀個 integration，唔 share 嘅嘢 API 一律報錯（就算 token 啱都睇唔到）。

## Codex CLI 嘅認證 🔐

兩條路任揀，全部由 `.env` 控制。

**A. 自訂 proxy（同 claude 一樣，env var 直通）**

```env
CODEX_AUTH_TOKEN=你個 token
CODEX_BASE_URL=你個 Responses API endpoint
```

寫入 `.env`，`make start` 之後 `docker-compose.yml` 自動 forward 入 workspace container。`codex` 已經被一個 shell function 包住：行命令時偵測到兩條 env 都有值，會自動補 `-c model_provider=...`、`base_url`、`wire_api=responses`、`requires_openai_auth=false` 等 inline override，直接指去你嘅 proxy。

⚠️ Codex CLI 由 2026/02 起 drop 咗 chat completions（`wire_api = "chat"`），淨返 OpenAI **Responses API**（`/v1/responses`）一條路。所以 `CODEX_BASE_URL` 指住嘅 endpoint **一定要識講 Responses API**（OpenAI 本家、Azure OpenAI、或者啲走 Responses-native 嘅 proxy）。如果你嘅 gateway 淨係識 chat completions（例如純 Anthropic-style proxy / OpenRouter），就要中間夾一層 translation bridge（[VibeAround](https://github.com/jazzenchen/VibeAround) 之類），或者乾脆 fallback 行 ChatGPT login。

**B. ChatGPT login（fallback，env 留空就行呢條）**

兩條 `CODEX_*` env 任何一條空白，`codex` function 會 fallback 行返原本流程。第一次入 workspace container 後行：

```bash
codex login --device-auth
```

跟住用 browser 開佢畀你嘅 link，輸入 device code 完成登入。登入資料會存喺 host 嘅 `.data/codex/`，再 mount 入 container 做 `/home/sandbox/.codex`，所以 rebuild / restart container 之後唔使重新 login。

兩條路都已經預設加 `--dangerously-bypass-approvals-and-sandbox`。呢個 sandbox 本身已經喺 Docker container 入面，日常用法會接近 `claude` 嗰種免確認流程。

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
├── .env / .env.example         # ClickHouse / MySQL credentials + Claude / Codex / gh / Notion token
├── Makefile                    # 全部 make 指令
├── Dockerfile                  # workspace 容器點 build
├── workspace/                  # 你嘅 workspace bind mount（gitignore）
├── .data/                      # MySQL / Redis 資料 + Claude Code / Codex 狀態 bind mount 落呢度（gitignore）
├── claude/                     # submodule，sasaya 個人 Claude 設定，mount 入容器做 /home/sandbox/.claude
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

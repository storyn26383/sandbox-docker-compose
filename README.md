# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse) 落到 `clickhouse/`，一齊跑，唔使重複維護。Claude 個人設定（skills / commands / settings）就用 [`storyn26383/.claude`](https://github.com/storyn26383/.claude) submodule 落到 `claude/`，再 mount 入 workspace container 做 `/home/sandbox/.claude`。

## 入面有咩 📦

**Dev container**（base：[`phpswoole/swoole:5.1-php8.3`](https://hub.docker.com/r/phpswoole/swoole)）

| 類別 | 有咩 |
|---|---|
| 🐘 程式語言 | PHP 8.3、Swoole 5.1、Bun、Node.js 22 |
| 🤖 CLI | claude-code、jq、ripgrep、fzf、htop |
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

由於 host 上面已經有自己嘅 MySQL / Redis / ClickHouse 喺度跑，sandbox 嘅 DB **全部唔 publish 到 host**，避免 port 撞。要由 host 連入嚟就行 SSH tunnel（下面 [SSH Tunnel 連 DB](#ssh-tunnel-連-db-) section 講）。

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
make ssh        # 透過 sshd 入 workspace container
make tunnel     # 開 SSH tunnel forward 所有 DB 到 localhost
make logs       # tail 晒所有 log
make reset      # 一鍵清晒（連 ClickHouse data 都冚）
```

## Workspace 📂

預設已經有一個 workspace mount：

| Host | 容器 |
|---|---|
| `./workspace/` | `/home/sandbox/workspace`（即 `~/workspace`） |

`make init` 會幫你預先 `mkdir` 好個目錄。Host 上面用任何 IDE 直接 edit `./workspace/...`，容器內即時見到（`make ssh` 入去就喺 `~/workspace`）。`./workspace/` 已經 `.gitignore`，唔會污染 repo。

因為 sandbox 用戶 UID/GID 跟住 host 一樣，permission 自動匹配，host 同容器寫嘅檔案兩邊都當係你本機 user 擁有。`git` 嘅 user.name / user.email 喺 `make build` 嗰陣由 Makefile 從 host `git config` 攞返，build 入 image，commit 即用即得。

## Claude Code 嘅認證 🔐

唔行 OAuth flow，靠 env var 直接通：

```env
ANTHROPIC_AUTH_TOKEN=你個 token
ANTHROPIC_BASE_URL=你個 proxy / gateway URL
```

寫入 `.env`（已 gitignore），`make start` 之後 `docker-compose.yml` 會自動 forward 入 workspace container，`claude` 啟動時直接攞嚟用，唔使再 login。

## SSH Tunnel 連 DB 🔌

Dev container 入面跑住 sshd，host 嘅 `127.0.0.1:2222` 對住容器嘅 `22`。SSH 認證用你 host 嘅 `~/.ssh/id_ed25519.pub`（mount 入容器做 `/home/sandbox/.ssh/authorized_keys`），login 帳戶係 `sandbox`（root login disabled），唔使輸密碼。`sandbox` 用戶嘅 UID/GID 跟你 host 一樣，喺 mount 入嚟嘅 project 度寫嘅檔案會係你本機 user 擁有。

**一鍵起晒 tunnel**（背景跑）

```bash
make tunnel &
```

呢個會 forward 哂下面嘅 port：

| Local port | 對應容器 |
|---|---|
| 13306 | `mysql:3306` |
| 16379 | `redis:6379` |
| 18123 | `clickhouse:8123` |
| 19000 | `clickhouse:9000` |
| 28123 | `clickhouse-testing:8123` |
| 29000 | `clickhouse-testing:9000` |

之後 host 上面照常連：

```bash
mysql -h 127.0.0.1 -P 13306 -uroot -proot
redis-cli -h 127.0.0.1 -p 16379
curl 'http://127.0.0.1:18123/?query=SELECT+1'
```

**SSH 直入 workspace container**（行任何指令都得）

```bash
make ssh
# 或者
ssh -p 2222 sandbox@localhost
```

**改 SSH port**

`.env` 入面改 `SANDBOX_SSH_PORT=...`，`make restart` 之後新 port 即時生效。

**唔想用 SSH，淨係喺 workspace container 入面做嘢**

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
├── .env / .env.example         # ClickHouse + MySQL credentials
├── Makefile                    # 全部 make 指令
├── Dockerfile                  # workspace 容器點 build
├── workspace/                  # 你嘅 workspace bind mount（gitignore）
├── .data/                      # MySQL / Redis 資料 bind mount 落呢度（gitignore）
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

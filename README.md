# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse)，一齊跑，唔使重複維護。Claude 個人設定（skills / commands / settings）就用 [`storyn26383/.claude`](https://github.com/storyn26383/.claude) submodule 落到 `claude/`，再 mount 入 dev container 做 `/root/.claude`。

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

容器之間照常用 service name 通到，例如喺 dev 容器內 `mysql -h mysql`、`redis-cli -h redis`、`curl http://clickhouse:8123`。

## 點樣開工 🚀

### 第一次 clone

```bash
git clone --recurse-submodules <呢個 repo 嘅 url>
cd sandbox-docker-compose
make init       # 拉 submodule、cp .env、build dev image，一句搞掂
make start
```

### Clone 完先發現唔記得 `--recurse-submodules`

```bash
git submodule update --init --recursive
```

### `.env`

`make init` 會自動 `cp .env.example .env`。入面啲嘢全部係本地最 chill 嘅預設值（`default` / `root`），要改自己 edit 就得。

## 平時點用 🎮

```bash
make start      # 起所有 service
make stop       # 全部停
make restart    # 重啟
make shell      # docker exec 入 dev container（pwd /app）
make ssh        # 透過 sshd 入 dev container
make tunnel     # 開 SSH tunnel forward 所有 DB 到 localhost
make logs       # tail 晒所有 log
make reset      # 一鍵清晒（連 ClickHouse data 都冚）
```

## Mount 自己個 project 入嚟做嘢 📂

Dev 容器**預設冇 mount 任何嘢**，因為唔想限死你寫邊個 project。要用嘅時候有兩種玩法：

**🎯 一次性**（試吓嘢咁）

```bash
docker compose run --rm -v ~/Coding/my-project:/app dev bash
```

**📌 長期**（成日返嚟搞同一個 project）

喺 repo 根新增 `docker-compose.override.yml`（已經 gitignore 咗，唔會污染 repo）：

```yaml
services:
  dev:
    volumes:
      - ~/Coding/my-project:/app
```

之後 `make restart` 就會自動帶住個 mount，再 `make shell` 入到去就直接喺 `/app` 見到你個 project。

## Claude Code 嘅認證 🔐

唔行 OAuth flow，靠 env var 直接通：

```env
ANTHROPIC_AUTH_TOKEN=你個 token
ANTHROPIC_BASE_URL=你個 proxy / gateway URL
```

寫入 `.env`（已 gitignore），`make start` 之後 `docker-compose.yml` 會自動 forward 入 dev container，`claude` 啟動時直接攞嚟用，唔使再 login。

## SSH Tunnel 連 DB 🔌

Dev container 入面跑住 sshd，host 嘅 `127.0.0.1:2222` 對住容器嘅 `22`。SSH 認證用你 host 嘅 `~/.ssh/id_ed25519.pub`（mount 入容器做 `authorized_keys`），唔使輸密碼。

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

**SSH 直入 dev container**（行任何指令都得）

```bash
make ssh
# 或者
ssh -p 2222 root@localhost
```

**改 SSH port**

`.env` 入面改 `SANDBOX_SSH_PORT=...`，`make restart` 之後新 port 即時生效。

**唔想用 SSH，淨係喺 dev container 入面做嘢**

```bash
make shell
# 入到 container 後直接：
mysql -h mysql -uroot -proot
redis-cli -h redis
curl 'http://clickhouse:8123/?query=SELECT+1'
```

## 結構 🗂️

```
sandbox-docker-compose/
├── docker-compose.yml          # 主 compose（include 埋 golden-clickhouse）
├── .env / .env.example         # ClickHouse + MySQL credentials
├── Makefile                    # 全部 make 指令
├── docker/dev/Dockerfile       # dev 容器點 build
├── claude/                     # submodule，sasaya 個人 Claude 設定，mount 入容器做 /root/.claude
└── golden-clickhouse/          # submodule，ClickHouse 嘅嘢全部喺呢度
```

## 想清乾淨重新嚟過 🧹

```bash
make reset
```

會做兩樣嘢：

1. `docker compose down -v` —— 停 service + 刪 named volume（MySQL / Redis 資料一齊冚）
2. `rm -rf golden-clickhouse/docker/.data/clickhouse` —— ClickHouse 數據都清

跟住 `make start` 就係全新一個。

## 提一提 ⚠️

- 要 Docker Compose **v2.20+**（用到 `include:` 指令）。Docker Desktop / OrbStack 2023-10 之後都得。
- ClickHouse 嘅 XML config（servers / macros / zookeeper / cors / timezone）由 submodule 提供，唔好喺 sandbox 度改；要改就入 `golden-clickhouse` repo 改完 push。
- Apple Silicon（M 系）行得通，全部 image / install script 都有 arm64 版。

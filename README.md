# sandbox-docker-compose 🧪

自己嘅開發沙盒，一個容器入面塞晒平時用嘅工具，再夾埋 MySQL / ClickHouse / Redis 三個 DB，方便試嘢、寫 demo、玩新 library 嗰陣唔使污染本機。

ClickHouse 嗰 part 直接用 git submodule 拉返 [`golden-clickhouse`](https://github.com/storyn26383/golden-clickhouse)，一齊跑，唔使重複維護。

## 入面有咩 📦

**Dev container**（base：[`phpswoole/swoole:5.1-php8.3`](https://hub.docker.com/r/phpswoole/swoole)）

| 類別 | 有咩 |
|---|---|
| 🐘 程式語言 | PHP 8.3、Swoole 5.1、Bun、Node.js 22 |
| 🤖 CLI | claude-code、jq、ripgrep、fzf、htop |
| 🔨 Build | composer、git、build-essential |
| 🗄️ DB client | mysql、redis-cli |
| 🌐 網絡 | curl、wget、ping、dig、nc |

**DB services**

| Service | Image | Host port |
|---|---|---|
| `mysql` | `mysql:8.0` | 3306 |
| `redis` | `redis:7-alpine` | 6379 |
| `clickhouse` | `clickhouse/clickhouse-server:23.3` | 8123 / 9000 |
| `clickhouse-testing` | `clickhouse/clickhouse-server:23.3` | 18123 / 19000 |

容器之間直接用 service name 通到，唔使理 IP。例如喺 dev 容器入面打 `mysql -h mysql`、`redis-cli -h redis`、`curl http://clickhouse:8123` 就得。

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
make shell      # 跳入 dev 容器嘅 bash，pwd 係 /app
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

## Claude Code 嘅 login 🔐

因為 dev 容器冇 mount `/root`，每次 rebuild image 之後 OAuth token 會冇，要再 login。

如果嫌煩想保住 login，喺 override file 加：

```yaml
services:
  dev:
    volumes:
      - dev-home:/root

volumes:
  dev-home:
```

咁 token 就會 keep 住喺 named volume 入面，rebuild image 都唔會冇。

## 連 DB 🔌

**由 host（即係你 Mac）連**

```bash
mysql -h 127.0.0.1 -P 3306 -uroot -proot
redis-cli -h 127.0.0.1 -p 6379
curl 'http://localhost:8123/?query=SELECT+1'
```

**由 dev 容器入面連**（用 service name）

```bash
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

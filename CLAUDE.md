# CLAUDE.md

呢個 repo 係 sasaya 自己用嘅開發沙盒（dev box）。下面係喺呢個 repo 做嘢嗰陣要記住嘅嘢。

## 寫文件嘅口氣

呢個 repo 入面嘅 README、notes、提示文字全部都係 sasaya 自己睇嘅，**用口語廣東話 + emoji 都得**，唔使跟全域 CLAUDE.md 嗰個書面語 / 排版指北規則。

例外：commit message、code comment（如真係要寫）、push 出去嘅嘢，照跟全域規則用英文 / 書面語。

## Submodule 紀律

`golden-clickhouse/` 係 git submodule，指住 `git@github.com:storyn26383/golden-clickhouse.git`。

- **唔好喺 sandbox 呢度直接改 `golden-clickhouse/` 入面任何檔案**（包括 XML config、docker-compose.yml、Makefile）。
- 要改 ClickHouse 設定就 `cd golden-clickhouse`，喺嗰邊 commit、push，再返嚟 sandbox 度 update submodule pointer。
- 如果發現 submodule 內有 dirty changes，先問清楚先動。

## Docker 操作嘅限制

Claude Code 嘅 sandbox 唔畀 access Docker socket（OrbStack / Docker Desktop 都係）。所以：

- `docker compose build`、`docker compose up`、`docker ps` 等指令喺 Claude session 入面**會 fail**。
- 要用家自己喺 terminal 行，或者你出指令叫佢行。
- 唔好嘥時間試嚟試去，直接話畀佢知要佢自己跑。

## Compose include 結構

- `docker-compose.yml` 用 `include:` 帶入 `golden-clickhouse/docker-compose.yml`。
- 顯式寫咗 `env_file: .env`，因為 golden-clickhouse 入面個 `.env` 係 broken symlink (`../api/.env`)。
- ClickHouse XML config 入面 `<host>clickhouse</host>` 係 service name，唔係 container name —— include 之後仲係喺同一個 network，仍然 resolve 到。
- 需要 Compose **v2.20+**（include 指令）。

## Dev container 設計原則

- **預設冇 mount 任何 host 目錄**。要 mount 由用家自己用 `docker-compose.override.yml` 加，已經 `.gitignore` 咗。
- Base image 用 `phpswoole/swoole:5.1-php8.3`（Debian bookworm），唔好提議轉 Alpine —— alpine variant 唔包 dev 工具，要重新填好多嘢。
- WORKDIR 係 `/app`。

## `.env` / 環境變數

- `.env.example` 係單一真相 —— 改 env key 一定要兩邊（`.env.example` 同 `.env`）一齊改。
- 預設值適合本機 chill 用（root / default），唔好提議改成「production-grade」。

## 唔好做嘅嘢

- **唔好幫手寫 Dockerfile health check / 多 stage build / production hardening**——呢個係 dev box，過度工程冇意義。
- **唔好加 backwards-compat 嘅 shim**（例如 PHP 8.2 fallback、Swoole 4.x 兼容）——一個版本搞掂。
- **唔好擅自改 ClickHouse port / service name**——會破壞 `golden-clickhouse` 內 XML hardcoded 嘅 host reference。

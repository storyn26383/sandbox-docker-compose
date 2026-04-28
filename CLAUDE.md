# CLAUDE.md

呢個 repo 係 sasaya 自己用嘅開發沙盒（dev box）。下面係喺呢個 repo 做嘢嗰陣要記住嘅嘢。

## 寫文件嘅口氣

呢個 repo 入面嘅 README、notes、提示文字全部都係 sasaya 自己睇嘅，**用口語廣東話 + emoji 都得**，唔使跟全域 CLAUDE.md 嗰個書面語 / 排版指北規則。

例外：commit message、code comment（如真係要寫）、push 出去嘅嘢，照跟全域規則用英文 / 書面語。

## Submodule 紀律

呢個 repo 有兩個 submodule：

| Path | Remote | 用途 |
|---|---|---|
| `clickhouse/` | `git@github.com:storyn26383/golden-clickhouse.git` | ClickHouse service 同 config |
| `claude/` | `git@github.com:storyn26383/.claude.git` | sasaya 個人 Claude 設定，mount 入 workspace container 做 `/home/sandbox/.claude` |

- **唔好喺 sandbox 呢度直接改 submodule 入面任何檔案**（包括 ClickHouse XML config、Claude skills/commands/settings）。
- 要改 ClickHouse / Claude 設定就 `cd <submodule>`，喺嗰邊 commit、push，再返嚟 sandbox 度 update submodule pointer。
- `claude/` 比較易變 dirty —— 因為 workspace container 入面 claude-code 會寫 runtime state（projects/、scheduled_tasks.json 等）入 mount，呢啲跟 `claude` submodule 自己嘅 `.gitignore` 處理。如果見到 dirty，要分清楚係 runtime 產物（無視）定真係改咗 config（去處理）。
- `claude/` mount 入 workspace container 之後喺容器內叫 `/home/sandbox/.claude`，唔係 `claude` —— mount target 唔同 path name。

## Docker 操作嘅限制

Claude Code 嘅 sandbox 唔畀 access Docker socket（OrbStack / Docker Desktop 都係）。所以：

- `docker compose build`、`docker compose up`、`docker ps` 等指令喺 Claude session 入面**會 fail**。
- 要用家自己喺 terminal 行，或者你出指令叫佢行。
- 唔好嘥時間試嚟試去，直接話畀佢知要佢自己跑。

## Compose include 結構

- `docker-compose.yml` 用 `include:` 帶入 `clickhouse/docker-compose.yml`（即 `golden-clickhouse` submodule）。
- 顯式寫咗 `env_file: .env`，因為 submodule 入面個 `.env` 係 broken symlink (`../api/.env`)。
- ClickHouse XML config 入面 `<host>clickhouse</host>` 係 service name，唔係 container name —— include 之後仲係喺同一個 network，仍然 resolve 到。
- 嗰邊帶過嚟嘅 `clickhouse` / `clickhouse-testing` 嘅 `ports:` 喺 sandbox 度用 `ports: !override []` **強制清空**（host 唔 publish），呢個係刻意嘅設計。
- 需要 Compose **v2.24+**（用到 `!override` tag）。

## Dev container 設計原則

- **預設 mount `./.data/workspace` 落 `/home/sandbox/workspace`** 做 workspace（host IDE edit、容器內 SSH/`make shell` 入去 `~/workspace` 即見）。`make init` 會預先 `mkdir`，避免 Docker daemon 以 root 創建令 sandbox 寫唔到。要加其他 mount 直接改 `docker-compose.yml`。
- Base image 用 `phpswoole/swoole:5.1-php8.3`（Debian bookworm），唔好提議轉 Alpine —— alpine variant 唔包 dev 工具，要重新填好多嘢。
- WORKDIR 係 `/home/sandbox/workspace`（即 sandbox 用戶嘅 `~/workspace`），同 host bind mount target 對齊，`make shell` / SSH 入去自然喺度。
- 容器內有兩個身份：
  - **`sandbox`** —— Build args `UID` / `GID` 跟 host 一致（`HOST_UID`/`HOST_GID`，default 1000/1000），有 NOPASSWD sudo。SSH login、mount 入嚟嘅 project 寫嘢、`make shell` 全部用 `sandbox`。
  - **`root`** —— sshd PID 1 必須 root 跑（auth、bind port），所以 image 嘅 `USER` 維持 root。`docker compose exec workspace bash` 預設都係 root；要 sandbox shell 就 `-u sandbox`（已喺 Makefile `make shell` 配好）。
- Container 跑住 **sshd**（CMD `/usr/sbin/sshd -D -e`），host 嘅 `127.0.0.1:${SANDBOX_SSH_PORT}:22` 對住 container 22 port，畀 host 透過 SSH tunnel 連 DB。
- SSH 認證**只接受 pubkey** + **禁止 root login**（`PermitRootLogin no` + `PasswordAuthentication no`），mount host 嘅 `${SSH_PUBKEY:-${HOME}/.ssh/id_ed25519.pub}` 做 `/home/sandbox/.ssh/authorized_keys`。SSH 一律以 `sandbox` 登入（`make ssh` / `make tunnel` 已配好）。
- Bun 系統級裝（`BUN_INSTALL=/usr/local`），唔放喺 `/root/.bun`，咁 sandbox 用戶都用到。
- DB services（mysql / redis / clickhouse / clickhouse-testing）**全部唔 publish 到 host**，純內網。要 host 連 DB 一律行 `make tunnel`。**唔好提議直接 publish DB port** —— 用家本機已經有自己嘅 DB 跑緊，會撞 port。

## `.env` / 環境變數

- `.env.example` 係單一真相 —— 改 env key 一定要兩邊（`.env.example` 同 `.env`）一齊改。
- 預設值適合本機 chill 用（root / default），唔好提議改成「production-grade」。
- `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` 由 `.env` 經 `docker-compose.yml` `environment:` forward 入 workspace container 畀 claude-code 用。**唔好提議用 OAuth flow** —— 已經設計成靠 token + proxy URL，唔需要 login。
- `SANDBOX_SSH_PORT`（host 上面嘅 SSH port，default 2222）同 `SSH_PUBKEY`（authorized_keys 嘅來源，default `${HOME}/.ssh/id_ed25519.pub`）由 compose `${VAR:-default}` 解析。
- `HOST_UID` / `HOST_GID` 由 Makefile 自動 `id -u` / `id -g` 注入並 export，唔放 `.env`，唔需要手動 set。**淨係透過 Makefile build / start**；如果直接 `docker compose build`，會 fallback 到 compose 預設嘅 `1000/1000`，會錯。

## 唔好做嘅嘢

- **唔好幫手寫 Dockerfile health check / 多 stage build / production hardening**——呢個係 dev box，過度工程冇意義。
- **唔好加 backwards-compat 嘅 shim**（例如 PHP 8.2 fallback、Swoole 4.x 兼容）——一個版本搞掂。
- **唔好擅自改 ClickHouse port / service name**——會破壞 `clickhouse/` submodule 內 XML hardcoded 嘅 host reference。

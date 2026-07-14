# Go 1.26.5 Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 workspace Docker 映像安裝並驗證 Go 官方穩定版 1.26.5，支援 Linux amd64 和 arm64。

**Architecture:** 在現有 Dockerfile 使用 Go 官方 tarball。建置時根據 Debian 架構選擇檔案及官方 SHA-256 checksum，驗證後解壓至 `/usr/local/go`；`PATH` 令所有 container 用戶可直接使用 `go`。README 只更新工具清單的版本資訊。

**Tech Stack:** Docker、Debian Bookworm、Go 官方二進位發佈檔、SHA-256。

---

## File structure

- `Dockerfile`：安裝並驗證 Go 1.26.5，提供 `/usr/local/go/bin/go`。
- `README.md`：列出 Go 1.26.5 為 dev container 的程式語言。

### Task 1: 安裝並驗證 Go 官方二進位檔

**Files:**
- Modify: `Dockerfile:9-12`
- Modify: `Dockerfile:59-60`
- Test: Docker 映像 build 後的 `go version` 指令

- [ ] **Step 1: 定義固定 Go 版本及執行路徑**

在 `Dockerfile` 第 12 行後加入以下設定：

```dockerfile
ARG GO_VERSION=1.26.5

ENV PATH=/usr/local/go/bin:${PATH}
```

`ARG` 令版本在 Docker build log 可見，預設固定在 1.26.5；`ENV PATH` 令 root 和 `sandbox` 用戶都有 `go` 指令。

- [ ] **Step 2: 加入按架構下載及 SHA-256 驗證的安裝步驟**

在 Bun 安裝的 `RUN` 指令後、Composer 安裝的 `RUN` 指令前，加入：

```dockerfile
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            go_archive="go${GO_VERSION}.linux-amd64.tar.gz"; \
            go_checksum="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"; \
            ;; \
        arm64) \
            go_archive="go${GO_VERSION}.linux-arm64.tar.gz"; \
            go_checksum="fe4789e92b1f33358680864bbe8704289e7bb5fc207d80623c308935bd696d49"; \
            ;; \
        *) \
            echo "Unsupported Go architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl --fail --location --show-error --silent "https://go.dev/dl/${go_archive}" --output "/tmp/${go_archive}"; \
    echo "${go_checksum}  /tmp/${go_archive}" | sha256sum --check; \
    tar -C /usr/local -xzf "/tmp/${go_archive}"; \
    rm "/tmp/${go_archive}"; \
    go version
```

固定官方 `amd64`／`arm64` checksum，避免下載或架構選擇錯誤時產生可用但不可信的映像。既有基底映像已經安裝 `curl`，而 Debian 的 `coreutils` 已提供 `sha256sum`，毋須加入套件。

- [ ] **Step 3: Build 映像並確認安裝成功**

由有 Docker 存取權的終端執行：

```bash
make build
```

預期 build 成功，並在 Go 安裝步驟出現：

```text
go version go1.26.5 linux/amd64
```

或者在 Apple Silicon 出現：

```text
go version go1.26.5 linux/arm64
```

- [ ] **Step 4: 在已啟動的 workspace 容器驗證 PATH 及版本**

由有 Docker 存取權的終端執行：

```bash
make start
make shell
```

在 container shell 執行：

```bash
command -v go
go version
```

預期輸出：

```text
/usr/local/go/bin/go
go version go1.26.5 linux/amd64
```

或在 Apple Silicon 為 `linux/arm64`。

### Task 2: 更新 README 工具清單

**Files:**
- Modify: `README.md:13`
- Test: `README.md` 的程式語言列

- [ ] **Step 1: 更新程式語言列**

將 `README.md` 的現有程式語言列：

```markdown
| 🐘 程式語言 | PHP 8.3、Swoole 6.0、Bun、Node.js 22 |
```

替換為：

```markdown
| 🐘 程式語言 | PHP 8.3、Swoole 6.0、Go 1.26.5、Bun、Node.js 22 |
```

- [ ] **Step 2: 檢查文件與 Dockerfile 使用同一版本**

執行：

```bash
grep -n 'GO_VERSION\|Go 1\.26\.5' Dockerfile README.md
```

預期同時找到 Dockerfile 的 `ARG GO_VERSION=1.26.5` 及 README 的 `Go 1.26.5`。

- [ ] **Step 3: 檢查最終 diff**

執行：

```bash
git diff --check
git diff -- Dockerfile README.md
```

預期 `git diff --check` 無輸出；diff 只涉及 Go 安裝及 README 工具列。

- [ ] **Step 4: 建立 commit（只限用戶明確授權時）**

在用戶明確要求提交後，執行：

```bash
git add Dockerfile README.md
git commit -m "feat: install Go"
```

預期新增一個只包含 `Dockerfile` 和 `README.md` 的 conventional commit。

## Plan self-review

- Spec coverage：Task 1 覆蓋 Go 1.26.5、amd64／arm64 選擇、checksum 驗證、非支援架構失敗、PATH 與執行驗收；Task 2 覆蓋 README。
- Placeholder scan：無 `TBD`、`TODO` 或未指定的驗證動作。
- Consistency：規格、Dockerfile 預設版本、README 及驗證輸出均為 Go 1.26.5。
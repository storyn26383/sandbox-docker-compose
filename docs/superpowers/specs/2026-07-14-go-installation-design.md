# Go 安裝設計

## 目標

在 workspace Docker 映像安裝 Go 官方目前最新穩定版 Go 1.26.5，供 `sandbox` 用戶直接使用 `go` 指令。

## 範圍

- 修改 `Dockerfile` 安裝 Go 1.26.5。
- 修改 `README.md` 的工具清單，列出 Go 1.26.5。
- 不改動 Compose 設定、Makefile、`.env` 或任何 submodule。

## 安裝方式

Docker build 時根據 `dpkg --print-architecture` 選取官方 Go 壓縮檔：

- `amd64`：`go1.26.5.linux-amd64.tar.gz`
- `arm64`：`go1.26.5.linux-arm64.tar.gz`

從 `https://go.dev/dl/` 下載檔案，使用已固定在 Dockerfile 的官方 SHA-256 checksum 驗證。驗證成功後，解壓至 `/usr/local/go`，並以 `ENV PATH=/usr/local/go/bin:${PATH}` 令所有用戶可直接執行 `go`。

不支援的架構會令 Docker build 立即失敗，避免安裝錯誤二進位檔。

## 錯誤處理

- 下載失敗：`curl --fail` 令 build 失敗。
- checksum 不符：`sha256sum --check` 令 build 失敗。
- 非 `amd64`／`arm64` 架構：印出架構名稱並結束 build。

## 驗證

重新 build 映像後，在 workspace 容器執行：

```bash
go version
```

輸出必須為 `go version go1.26.5`，並顯示目前 Linux 架構。

## 版本更新

將來升級 Go 時，更新 Dockerfile 的版本常數、兩個平台的官方 SHA-256 checksum，以及 README 的版本文字。
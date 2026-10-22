FROM phpswoole/swoole:6.2-php8.5

# ==============================================================================
# Base build environment
# ==============================================================================
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Hong_Kong \
    LANG=en_US.UTF-8

# ==============================================================================
# System packages and locale
# ==============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && wget -nv -O /etc/apt/keyrings/cloudflare-main.gpg https://pkg.cloudflare.com/cloudflare-main.gpg \
    && chmod go+r /etc/apt/keyrings/cloudflare-main.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main" > /etc/apt/sources.list.d/cloudflared.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git vim sudo unzip zip xz-utils \
        clang cmake ninja-build pkg-config \
        gh cloudflared jq ripgrep fzf htop direnv \
        chromium \
        iputils-ping dnsutils netcat-openbsd \
        locales tzdata \
        default-mysql-client redis-tools \
        libmpdec-dev libjpeg-dev libpng-dev libicu-dev libzip-dev \
    && sed -i 's/^# *\(en_US.UTF-8\|zh_HK.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Sandbox user
# ==============================================================================
ARG UID=1000
ARG GID=1000
ARG USERNAME=sandbox
ARG GIT_USER_NAME=
ARG GIT_USER_EMAIL=

RUN groupadd -g ${GID} ${USERNAME} 2>/dev/null || true \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && echo "alias claude='claude --allow-dangerously-skip-permissions'" >> /home/${USERNAME}/.bashrc \
    && echo 'eval "$(direnv hook bash)"' >> /home/${USERNAME}/.bashrc \
    && printf '[user]\n\tname = %s\n\temail = %s\n[core]\n\texcludesfile = /home/%s/.gitignore_global\n' "${GIT_USER_NAME}" "${GIT_USER_EMAIL}" "${USERNAME}" > /home/${USERNAME}/.gitconfig \
    && printf '.envrc\n' > /home/${USERNAME}/.gitignore_global \
    && printf '[client]\nssl=0\n' > /home/${USERNAME}/.my.cnf \
    && chown ${UID}:${GID} /home/${USERNAME}/.bashrc /home/${USERNAME}/.gitconfig /home/${USERNAME}/.gitignore_global /home/${USERNAME}/.my.cnf

# ==============================================================================
# Node.js and global CLI tools
# ==============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code @fission-ai/openspec ccusage ntn \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Bun
# ==============================================================================
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

# ==============================================================================
# Go
# ==============================================================================
ARG GO_VERSION=1.26.5
ENV PATH=/usr/local/go/bin:${PATH}

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

# ==============================================================================
# rtk (Rust Token Killer)
# ==============================================================================
ARG RTK_VERSION=0.43.0

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            rtk_archive="rtk-x86_64-unknown-linux-musl.tar.gz"; \
            rtk_checksum="ff8a1e7766496e175291a85aeca1dc97c9ff6df33e51e5893d1fbc78fea2a609"; \
            ;; \
        arm64) \
            rtk_archive="rtk-aarch64-unknown-linux-gnu.tar.gz"; \
            rtk_checksum="5519f7ca12e5c143a609f0d28a0a77b97413a8dce31c2681f1a41c24519a8731"; \
            ;; \
        *) \
            echo "Unsupported rtk architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl --fail --location --show-error --silent "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/${rtk_archive}" --output "/tmp/${rtk_archive}"; \
    echo "${rtk_checksum}  /tmp/${rtk_archive}" | sha256sum --check; \
    tar -C /usr/local/bin -xzf "/tmp/${rtk_archive}"; \
    rm "/tmp/${rtk_archive}"; \
    rtk --version

# ==============================================================================
# glab (GitLab CLI)
# ==============================================================================
ARG GLAB_VERSION=1.116.0

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            glab_checksum="173cc61ea94c562f2ccd831f320d25b73982192e82810064552282482e3713ea"; \
            ;; \
        arm64) \
            glab_checksum="3e59a0c5db5b281c552543cc1018873ecdd551b07737cfdb932c6543aa39d88c"; \
            ;; \
        *) \
            echo "Unsupported glab architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    glab_archive="glab_${GLAB_VERSION}_linux_$(dpkg --print-architecture).tar.gz"; \
    curl --fail --location --show-error --silent "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/${glab_archive}" --output "/tmp/${glab_archive}"; \
    echo "${glab_checksum}  /tmp/${glab_archive}" | sha256sum --check; \
    tar -C /usr/local -xzf "/tmp/${glab_archive}" bin/glab; \
    rm "/tmp/${glab_archive}"; \
    glab --version

# ==============================================================================
# sentry-cli
# ==============================================================================
ARG SENTRY_CLI_VERSION=3.8.0

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            sentry_cli_binary="sentry-cli-Linux-x86_64"; \
            sentry_cli_checksum="13f8cb34ae01a6a272d7d7c22e277a105286615b4020de900ea95a8de47cdbb6"; \
            ;; \
        arm64) \
            sentry_cli_binary="sentry-cli-Linux-aarch64"; \
            sentry_cli_checksum="eaea24b5b47b61a96d9a2e353268ea41fd9a8c5b7979694330df614d4af672bf"; \
            ;; \
        *) \
            echo "Unsupported sentry-cli architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl --fail --location --show-error --silent "https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/${sentry_cli_binary}" --output /usr/local/bin/sentry-cli; \
    echo "${sentry_cli_checksum}  /usr/local/bin/sentry-cli" | sha256sum --check; \
    chmod +x /usr/local/bin/sentry-cli; \
    sentry-cli --version

# ==============================================================================
# Slack CLI
# ==============================================================================
ARG SLACK_CLI_VERSION=4.9.0

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            slack_cli_checksum="6fb005b3d49f02eacd281adcfccb446648dc784171d0e2b8e80bb648673d696a"; \
            ;; \
        arm64) \
            slack_cli_checksum="e63e11a60b563d0eb1e1505be1a97c1e4bf0e684fdf549d69c0619b770553344"; \
            ;; \
        *) \
            echo "Unsupported Slack CLI architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    slack_cli_archive="slack_cli_${SLACK_CLI_VERSION}_linux_$(dpkg --print-architecture).tar.gz"; \
    curl --fail --location --show-error --silent "https://downloads.slack-edge.com/slack-cli/${slack_cli_archive}" --output "/tmp/${slack_cli_archive}"; \
    echo "${slack_cli_checksum}  /tmp/${slack_cli_archive}" | sha256sum --check; \
    tar -C /usr/local -xzf "/tmp/${slack_cli_archive}" bin/slack; \
    rm "/tmp/${slack_cli_archive}"; \
    slack version

# ==============================================================================
# clickup-cli
# ==============================================================================
ARG CLICKUP_CLI_VERSION=0.18.0

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            clickup_cli_archive="clickup-linux-x86_64.tar.gz"; \
            clickup_cli_checksum="f88cc1373a5ca1ed0a204300f6eff84f5275e9f35aa50b0e6a08b77046f35cb6"; \
            ;; \
        arm64) \
            clickup_cli_archive="clickup-linux-arm64.tar.gz"; \
            clickup_cli_checksum="bc0e7482e9b9f6fc7c04bc04f7bf0797cc7fdd140097818c8068fe528b21ac6c"; \
            ;; \
        *) \
            echo "Unsupported clickup-cli architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl --fail --location --show-error --silent "https://github.com/nicholasbester/clickup-cli/releases/download/v${CLICKUP_CLI_VERSION}/${clickup_cli_archive}" --output "/tmp/${clickup_cli_archive}"; \
    echo "${clickup_cli_checksum}  /tmp/${clickup_cli_archive}" | sha256sum --check; \
    tar -C /usr/local/bin -xzf "/tmp/${clickup_cli_archive}" clickup-cli; \
    rm "/tmp/${clickup_cli_archive}"; \
    clickup-cli --version

# ==============================================================================
# protoc
# ==============================================================================
ARG PROTOC_VERSION=26.1

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) \
            protoc_archive="protoc-${PROTOC_VERSION}-linux-x86_64.zip"; \
            protoc_checksum="a7be2928c0454f132c599e25b79b7ad1b57663f2337d7f7e468a1d59b98ec1b0"; \
            ;; \
        arm64) \
            protoc_archive="protoc-${PROTOC_VERSION}-linux-aarch_64.zip"; \
            protoc_checksum="64a3b3b5f7dac0c8f9cf1cb85b2b1a237eb628644f6bcb0fb8f23db6e0d66181"; \
            ;; \
        *) \
            echo "Unsupported protoc architecture: $(dpkg --print-architecture)" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl --fail --location --show-error --silent "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${protoc_archive}" --output "/tmp/${protoc_archive}"; \
    echo "${protoc_checksum}  /tmp/${protoc_archive}" | sha256sum --check; \
    unzip -q "/tmp/${protoc_archive}" 'bin/protoc' 'include/*' -d /usr/local; \
    rm "/tmp/${protoc_archive}"; \
    protoc --version

# ==============================================================================
# Rust
# ==============================================================================
ARG RUST_VERSION=1.89.0
ARG FLUTTER_RUST_BRIDGE_CODEGEN_VERSION=2.13.0-beta.2
ARG CARGO_AUDIT_VERSION=0.22.2
ENV PATH=/home/${USERNAME}/.cargo/bin:${PATH}

USER ${USERNAME}

# Targets mirror openim-app's rust-toolchain.toml; rustup installs any missing ones on first cargo run anyway
RUN set -eux; \
    curl --proto '=https' --tlsv1.2 --fail --show-error --silent https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
            --component clippy --component rustfmt; \
    rustup target add \
        x86_64-unknown-linux-gnu \
        aarch64-apple-darwin x86_64-apple-darwin \
        aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios \
        aarch64-linux-android armv7-linux-androideabi x86_64-linux-android \
        x86_64-pc-windows-msvc; \
    rustc --version

RUN set -eux; \
    cargo install --locked flutter_rust_bridge_codegen --version "${FLUTTER_RUST_BRIDGE_CODEGEN_VERSION}"; \
    cargo install --locked cargo-audit --version "${CARGO_AUDIT_VERSION}"; \
    rm -rf "${HOME}/.cargo/registry" "${HOME}/.cargo/git"; \
    flutter_rust_bridge_codegen --version; \
    cargo audit --version

USER root

# ==============================================================================
# Flutter and melos
# ==============================================================================
ARG FLUTTER_VERSION=3.44.1
ARG FLUTTER_HOME=/home/${USERNAME}/flutter
ARG MELOS_VERSION=7.8.0
ENV PATH=${FLUTTER_HOME}/bin:/home/${USERNAME}/.pub-cache/bin:${PATH} \
    MELOS_SDK_PATH=${FLUTTER_HOME}

USER ${USERNAME}

RUN set -eux; \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}"; \
    flutter config --no-analytics; \
    dart --disable-analytics; \
    flutter precache --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia; \
    dart pub global activate melos "${MELOS_VERSION}"; \
    melos --version

USER root

# ==============================================================================
# PHP: Composer, extensions, and Swoole config
# ==============================================================================
RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

RUN docker-php-ext-configure gd --with-jpeg \
    && docker-php-ext-install bcmath gd intl pcntl zip \
    && pecl install decimal-2.0.1 \
    && docker-php-ext-enable decimal \
    && echo 'swoole.use_shortname=Off' > "${PHP_INI_DIR}/conf.d/zz-swoole.ini" \
    && rm -rf /tmp/pear

WORKDIR /home/sandbox/workspace
CMD ["sleep", "infinity"]

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
        git vim sudo unzip zip \
        gh cloudflared jq ripgrep fzf htop direnv \
        chromium \
        iputils-ping dnsutils netcat-openbsd \
        locales tzdata \
        default-mysql-client redis-tools \
        libmpdec-dev libjpeg-dev libpng-dev libicu-dev libzip-dev \
    && locale-gen en_US.UTF-8 zh_HK.UTF-8 \
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
    && echo 'codex() { if [ -n "$CODEX_AUTH_TOKEN" ] && [ -n "$CODEX_BASE_URL" ]; then command codex --dangerously-bypass-approvals-and-sandbox -c "model_provider=\"proxy\"" -c "model_providers.proxy.name=\"Sandbox proxy\"" -c "model_providers.proxy.base_url=\"$CODEX_BASE_URL\"" -c "model_providers.proxy.env_key=\"CODEX_AUTH_TOKEN\"" -c "model_providers.proxy.wire_api=\"responses\"" -c "model_providers.proxy.requires_openai_auth=false" "$@"; else command codex --dangerously-bypass-approvals-and-sandbox "$@"; fi; }' >> /home/${USERNAME}/.bashrc \
    && printf '%s\n' \
        '# ponytail: typo guard only, bypassable via `command ntn`.' \
        '# The real write barrier is the Notion PAT capabilities (grant "Read content" alone).' \
        'ntn() {' \
        '    case "$*" in' \
        '        api|api\ *|pages\ get\ *|datasources\ query\ *|datasources\ resolve\ *|files\ get\ *|files\ list|doctor|--help|-h|--version|-V) ;;' \
        '        *) echo "ntn: read-only mode, command blocked" >&2; return 1 ;;' \
        '    esac' \
        '    for arg in "$@"; do' \
        '        case "$arg" in' \
        '            *==*) continue ;;' \
        '            -X*|--data*|--unsafe-verbose|*=*) echo "ntn: read-only mode, $arg blocked" >&2; return 1 ;;' \
        '        esac' \
        '    done' \
        '    command ntn "$@"' \
        '}' \
        >> /home/${USERNAME}/.bashrc \
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
    && npm install -g @anthropic-ai/claude-code @openai/codex @fission-ai/openspec ccusage ntn \
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

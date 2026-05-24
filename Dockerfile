FROM phpswoole/swoole:5.1-php8.3

ARG UID=1000
ARG GID=1000
ARG USERNAME=sandbox
ARG GIT_USER_NAME=
ARG GIT_USER_EMAIL=

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Hong_Kong
ENV LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git vim sudo openssh-client openssh-server unzip zip \
        gh jq ripgrep fzf htop direnv \
        iputils-ping dnsutils netcat-openbsd \
        locales tzdata \
        default-mysql-client redis-tools \
        libmpdec-dev \
    && locale-gen en_US.UTF-8 zh_HK.UTF-8 \
    && mkdir -p /run/sshd \
    && sed -ri \
        -e 's/^#?PermitRootLogin.*/PermitRootLogin no/' \
        -e 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g ${GID} ${USERNAME} 2>/dev/null || true \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && mkdir -p /home/${USERNAME}/.ssh \
    && chown ${UID}:${GID} /home/${USERNAME}/.ssh \
    && chmod 700 /home/${USERNAME}/.ssh \
    && echo "alias claude='claude --allow-dangerously-skip-permissions'" >> /home/${USERNAME}/.bashrc \
    && echo 'codex() { if [ -n "$CODEX_AUTH_TOKEN" ] && [ -n "$CODEX_BASE_URL" ]; then command codex --dangerously-bypass-approvals-and-sandbox -c "model_provider=\"proxy\"" -c "model_providers.proxy.name=\"Sandbox proxy\"" -c "model_providers.proxy.base_url=\"$CODEX_BASE_URL\"" -c "model_providers.proxy.env_key=\"CODEX_AUTH_TOKEN\"" -c "model_providers.proxy.wire_api=\"responses\"" -c "model_providers.proxy.requires_openai_auth=false" "$@"; else command codex --dangerously-bypass-approvals-and-sandbox "$@"; fi; }' >> /home/${USERNAME}/.bashrc \
    && echo 'eval "$(direnv hook bash)"' >> /home/${USERNAME}/.bashrc \
    && printf '[user]\n\tname = %s\n\temail = %s\n[core]\n\texcludesfile = /home/%s/.gitignore_global\n' "${GIT_USER_NAME}" "${GIT_USER_EMAIL}" "${USERNAME}" > /home/${USERNAME}/.gitconfig \
    && printf '.envrc\n' > /home/${USERNAME}/.gitignore_global \
    && printf '[client]\nssl=0\n' > /home/${USERNAME}/.my.cnf \
    && chown ${UID}:${GID} /home/${USERNAME}/.bashrc /home/${USERNAME}/.gitconfig /home/${USERNAME}/.gitignore_global /home/${USERNAME}/.my.cnf

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code @openai/codex \
    && rm -rf /var/lib/apt/lists/*

ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

RUN pecl install decimal-1.5.0 \
    && docker-php-ext-enable decimal

WORKDIR /home/sandbox/workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]

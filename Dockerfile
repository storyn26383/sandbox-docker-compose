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
        git vim sudo openssh-client openssh-server unzip zip \
        jq ripgrep fzf htop \
        iputils-ping dnsutils netcat-openbsd \
        locales tzdata \
        default-mysql-client redis-tools \
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
    && echo "alias codex='codex --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check'" >> /home/${USERNAME}/.bashrc \
    && printf '[user]\n\tname = %s\n\temail = %s\n' "${GIT_USER_NAME}" "${GIT_USER_EMAIL}" > /home/${USERNAME}/.gitconfig \
    && chown ${UID}:${GID} /home/${USERNAME}/.bashrc /home/${USERNAME}/.gitconfig

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @anthropic-ai/claude-code @openai/codex \
    && rm -rf /var/lib/apt/lists/*

ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

RUN curl -sS https://getcomposer.org/installer \
    | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /home/sandbox/workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]

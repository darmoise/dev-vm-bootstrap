FROM debian:bookworm-slim

ARG UID=1000
ARG GID=1000

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Minimal utilities required by Claude and for downloading/unpacking toolchains.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    ripgrep \
    less \
    procps \
    openssh-client \
    unzip \
    zip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Non-root user whose numeric UID/GID match the Fedora host user.
RUN groupadd --gid "${GID}" developer \
    && useradd \
        --create-home \
        --uid "${UID}" \
        --gid "${GID}" \
        --shell /bin/bash \
        developer

USER developer

ENV HOME=/home/developer
ENV CLAUDE_CONFIG_DIR=/home/developer/.claude
ENV AGENT_DATA=/home/developer/.agent-data
ENV GRADLE_USER_HOME=/home/developer/.agent-data/gradle
ENV ANDROID_USER_HOME=/home/developer/.agent-data/android
ENV ANDROID_SDK_ROOT=/home/developer/.agent-data/toolchains/android-sdk
ENV XDG_CACHE_HOME=/home/developer/.agent-data/cache
ENV PATH="/home/developer/.local/bin:${PATH}"

# These directories are populated into Docker named volumes on first use,
# preserving ownership by the unprivileged developer user.
RUN mkdir -p \
    /home/developer/.claude \
    /home/developer/.agent-data/toolchains \
    /home/developer/.agent-data/gradle \
    /home/developer/.agent-data/maven \
    /home/developer/.agent-data/android \
    /home/developer/.agent-data/cache \
    && ln -s /home/developer/.agent-data/maven /home/developer/.m2

# Official Claude Code native installer. It runs as the unprivileged user.
# Residual supply-chain note: Anthropic currently documents this installer URL,
# but it is not pinned by an externally published checksum here.
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace
ENTRYPOINT ["claude"]

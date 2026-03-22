# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=openclaw-sandbox-common:bookworm-slim
FROM ${BASE_IMAGE}

USER root

# Install Docker CLI and other extras using our custom script
COPY install.sh /tmp/install.sh
RUN --mount=type=cache,id=openclaw-sandbox-bookworm-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=openclaw-sandbox-bookworm-apt-lists,target=/var/lib/apt,sharing=locked \
    bash /tmp/install.sh && rm /tmp/install.sh

USER sandbox
WORKDIR /home/sandbox

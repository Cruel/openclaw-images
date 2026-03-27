ARG OPENCLAW_NODE_IMAGE="node:24-bookworm-slim@sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"
FROM ${OPENCLAW_NODE_IMAGE}


ENV DEBIAN_FRONTEND=noninteractive \
    DOCKER_VERSION=29.3.1 \
    DOCKER_COMPOSE_VERSION=v5.1.1 \
    CONTAINER_SYSBOX_VERSION=0.7.0

# Install system components, Docker, and create openclaw user
COPY install.sh /usr/local/bin/install.sh
COPY iptables-loader.service /etc/systemd/system/iptables-loader.service
COPY predicate-authorityd.service /etc/systemd/system/predicate-authorityd.service
COPY mitm-proxy.service /etc/systemd/system/mitm-proxy.service
COPY openclaw-node.service /etc/systemd/system/openclaw-node.service

# Install system and register services
RUN chmod +x /usr/local/bin/install.sh && \
    /usr/local/bin/install.sh && \
    rm /usr/local/bin/install.sh

# Make use of stopsignal (instead of sigterm) to stop systemd containers.
STOPSIGNAL SIGRTMIN+3

# Volume /var/lib/docker to avoid storage driver issues
VOLUME /var/lib/docker

# Set working directory to openclaw home
WORKDIR /home/node

# Set systemd as entrypoint.
# Note: For systemd containers, the entrypoint must remain as /sbin/init (root).
ENTRYPOINT [ "/sbin/init", "--log-level=err" ]
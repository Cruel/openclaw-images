#!/bin/bash
set -e

# Systemd installation
apt-get update
apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    libsystemd0 \
    ca-certificates \
    dbus \
    iptables \
    iproute2 \
    kmod \
    locales \
    sudo \
    udev \
    curl \
    jq \
    procps

# Prevents journald from reading kernel messages from /dev/kmsg
echo "ReadKMsg=no" >> /etc/systemd/journald.conf

# Disable systemd services/units that are unnecessary within a container.
systemctl mask systemd-udevd.service \
    systemd-udevd-kernel.socket \
    systemd-udevd-control.socket \
    systemd-modules-load.service \
    sys-kernel-debug.mount \
    sys-kernel-tracing.mount \
    sys-kernel-config.mount \
    e2scrub_reap.service \
    e2scrub_all.timer

# Set iptables-legacy (was required for Ubuntu 22.04, not sure about Debian)
update-alternatives --set iptables /usr/sbin/iptables-legacy


# Detect architecture once at the top
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_ARCH="x64"; MITM_ARCH="x86_64"; SYSBOX_ARCH="amd64" ;;
    aarch64) BIN_ARCH="arm64"; MITM_ARCH="aarch64"; SYSBOX_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install Docker
curl -fsSL https://get.docker.com | sh -s -- --version "$DOCKER_VERSION"

# Install Docker Compose
curl --retry 5 --retry-max-time 40 \
    -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod 755 /usr/local/bin/docker-compose
mkdir -p /usr/local/lib/docker/cli-plugins
ln -s /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose

# Add Docker bash completion
mkdir -p /etc/bash_completion.d
curl -fsSL https://raw.githubusercontent.com/docker/docker-ce/master/components/cli/contrib/completion/bash/docker -o /etc/bash_completion.d/docker.sh

# Install Sysbox
curl -fL "https://downloads.nestybox.com/sysbox/releases/v${CONTAINER_SYSBOX_VERSION}/sysbox-ce_${CONTAINER_SYSBOX_VERSION}-0.linux_${SYSBOX_ARCH}.deb" -o /tmp/sysbox.deb

# Use dpkg-divert to forcefully mock sysctl in /sbin so dpkg respects it
dpkg-divert --add --rename --divert /sbin/sysctl.real /sbin/sysctl
ln -s /bin/true /sbin/sysctl

apt-get install -y /tmp/sysbox.deb

# Restore sysctl
rm /sbin/sysctl
dpkg-divert --remove --rename /sbin/sysctl

# 4. Install Security Guardians
MITMPROXY_VERSION="12.2.1"
echo "Installing Mitmproxy $MITMPROXY_VERSION for $ARCH..."
curl -fsSL "https://downloads.mitmproxy.org/${MITMPROXY_VERSION}/mitmproxy-${MITMPROXY_VERSION}-linux-${MITM_ARCH}.tar.gz" | tar -xzf - -C /usr/local/bin/

echo "Installing Predicate Guardian for $ARCH..."
curl -fsSL "https://github.com/PredicateSystems/predicate-authority-sidecar/releases/latest/download/predicate-authorityd-linux-${BIN_ARCH}.tar.gz" | tar -xzf -
chmod +x predicate-authorityd
mv predicate-authorityd /usr/local/bin/

# Create dedicated security users (system range to avoid UID 1000s)
useradd --system --shell /bin/false mitm-proxy
useradd --system --create-home --shell /bin/bash predicate

# Create restricted configuration directories for Guardians
# This prevents 'openclaw' user from reading policies and filters
mkdir -p /etc/predicate && chmod 700 /etc/predicate
mkdir -p /etc/mitmproxy && chmod 750 /etc/mitmproxy
chown -R predicate:predicate /etc/predicate
chown -R mitm-proxy:mitm-proxy /etc/mitmproxy

# Mask services of no use inside the container
systemctl mask getty.service getty.target
# systemctl mask systemd-logind.service

# Force overlay2 storage driver
mkdir -p /etc/docker && echo '{"storage-driver":"overlay2"}' > /etc/docker/daemon.json

# Configure existing 'node' user (UID 1000) and groups
groupmod -g 997 docker || true
groupadd -g 1001 sysbox || true
usermod -aG docker node
echo "node:node" | chpasswd
mkdir -p /home/node/.openclaw && chown -R node:node /home/node

# Enable lingering for 'node' user
mkdir -p /var/lib/systemd/linger
touch /var/lib/systemd/linger/node

useradd --create-home --shell /bin/bash admin
echo "admin:admin" | chpasswd
usermod -aG sudo,docker admin
echo "admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Enable services
systemctl enable iptables-loader predicate-authorityd mitm-proxy openclaw-node

# Setup mitm-proxy home
mkdir -p /home/mitm-proxy/.mitmproxy && chown -R mitm-proxy:mitm-proxy /home/mitm-proxy

# Housekeeping
apt-get clean -y
rm -rf \
    /var/cache/debconf/* \
    /var/lib/apt/lists/* \
    /var/log/* \
    /tmp/* \
    /var/tmp/* \
    /usr/share/doc/* \
    /usr/share/man/* \
    /usr/share/local/*

#!/usr/bin/env bash
set -euo pipefail

# Make it non-interactive
export DEBIAN_FRONTEND=noninteractive

# Install docker dependencies
apt-get update
apt-get install -y gnupg gh yq dnsutils iputils-ping

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
# We use the current OS codename from /etc/os-release (expected "bookworm" in the sandbox)
echo "Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc" > /etc/apt/sources.list.d/docker.sources

apt-get update
apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin
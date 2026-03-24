#!/usr/bin/env bash
set -euo pipefail

# Configuration
GEN_COMMENT="# GENERATED: DO NOT EDIT"
COMPOSE_DIR="./compose"

# Detect Host Docker GID
DOCKER_SOCKET="/var/run/docker.sock"
if [ -S "$DOCKER_SOCKET" ]; then
  # Try Linux (stat -c) and macOS (stat -f)
  DOCKER_GID="$(stat -c '%g' "$DOCKER_SOCKET" 2>/dev/null || stat -f '%g' "$DOCKER_SOCKET" 2>/dev/null || echo '')"
  if [ -n "$DOCKER_GID" ]; then
    echo "Detected Host Docker GID: $DOCKER_GID"
  else
    DOCKER_GID="999"
    echo "WARNING: Could not determine GID of $DOCKER_SOCKET. Falling back to default: 999"
  fi
else
  DOCKER_GID="999"
  echo "WARNING: Docker socket not found at $DOCKER_SOCKET. Using default: 999"
fi

# Environment Detection
IS_WSL2=false
if grep -qiE "microsoft|WSL2" /proc/version 2>/dev/null; then
  IS_WSL2=true
  echo "Detected environment: WSL2"
fi

HAS_SYSBOX=false
if docker info 2>/dev/null | grep -q "sysbox-runc"; then
  HAS_SYSBOX=true
  echo "Detected environment: Sysbox established"
fi

# Select default runtime and privileged mode
RUNTIME="runc"
PRIVILEGED="true" # Default to host-privileged for runc DinD
if [ "$HAS_SYSBOX" = true ] && [ "$IS_WSL2" = false ]; then
  RUNTIME="sysbox-runc"
  PRIVILEGED="false"
  echo "Automated choice: Using sysbox-runc (No privileged mode needed)"
else
  if [ "$IS_WSL2" = true ]; then
    echo "Automated choice: Using runc + privileged (Sysbox may have issues on WSL2)"
  else
    echo "Automated choice: Using runc + privileged (Sysbox not detected)"
  fi
fi

# Handle Configuration Templates and Directories
echo "Ensuring configuration directories exist..."
mkdir -p "$COMPOSE_DIR/gateway_config"
mkdir -p "$COMPOSE_DIR/node_config"
mkdir -p "$COMPOSE_DIR"
for template in "$COMPOSE_DIR"/*.default.*; do
  [ -e "$template" ] || continue
  
  base_template=$(basename "$template")
  target_name="${base_template//.default/}"
  
  if [ "$target_name" == "openclaw.json" ]; then
    target="$COMPOSE_DIR/gateway_config/openclaw.json"
  else
    target="$COMPOSE_DIR/$target_name"
  fi
  
  if [ ! -f "$target" ]; then
    cp "$template" "$target"
    echo "  Created $target from template"
  else
    echo "  Skipping $target (already exists)"
  fi
done

# Update .env file
ENV_FILE="$COMPOSE_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  touch "$ENV_FILE"
fi

# Update or add configurations
tmp_env=$(mktemp)

# Prepend Managed Variables
echo "DOCKER_GID=$DOCKER_GID $GEN_COMMENT" >> "$tmp_env"
echo "OPENCLAW_NODE_RUNTIME=$RUNTIME $GEN_COMMENT" >> "$tmp_env"
echo "OPENCLAW_NODE_PRIVILEGED=$PRIVILEGED $GEN_COMMENT" >> "$tmp_env"

# Handle Gateway Token
if grep -q "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE"; then
  # Preserve existing token
  grep "^OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" >> "$tmp_env"
else
  # Generate or set placeholder
  DEFAULT_TOKEN=$(openssl rand -hex 16 2>/dev/null || echo "")
  if [ -n "$DEFAULT_TOKEN" ]; then
    echo "OPENCLAW_GATEWAY_TOKEN=$DEFAULT_TOKEN $GEN_COMMENT" >> "$tmp_env"
    echo "Generated a new OPENCLAW_GATEWAY_TOKEN"
  else
    echo "OPENCLAW_GATEWAY_TOKEN=CHANGE_THIS_TO_SOMETHING_SECURE" >> "$tmp_env"
    echo "--------------------------------------------------------------------------------"
    echo "CRITICAL WARNING: FAILED TO GENERATE SECURE GATEWAY TOKEN!"
    echo "A placeholder has been set: CHANGE_THIS_TO_SOMETHING_SECURE"
    echo "THIS IS INSECURE. Please manually set OPENCLAW_GATEWAY_TOKEN in $ENV_FILE."
    echo "--------------------------------------------------------------------------------"
  fi
fi

# Append remaining existing configuration
grep -Ev "^(DOCKER_GID|OPENCLAW_NODE_RUNTIME|OPENCLAW_NODE_PRIVILEGED|OPENCLAW_GATEWAY_TOKEN)=" "$ENV_FILE" >> "$tmp_env" || true

mv "$tmp_env" "$ENV_FILE"
echo "Updated $ENV_FILE with GID, RUNTIME, and PRIVILEGED."

echo "Setup complete! You can now run: cd compose && docker compose up -d"

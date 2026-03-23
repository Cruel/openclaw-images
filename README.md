# OpenClaw Docker Infrastructure

This repository defines the infrastructure, deployment configurations, and secure sandbox environments for hosting **OpenClaw**. It uses a multi-layered containerized architecture to provide high security out-of-the-box, ensuring robust isolation between the control-plane gateway, task workers, and task sandboxes.

## Architecture & Setup Overview

The standard deployment configuration runs on the host using Docker Compose and orchestrates three primary services:

1. **OpenClaw Gateway**: Acts as the central control plane, receiving tasks and orchestrating agents.
2. **OpenClaw Secure Node (`openclaw-node`)**: A privileged systemd-based container acting as an independent, highly isolated virtual machine. It runs its own internal Docker-in-Docker daemon, networking stack, and security proxies. Inside this environment, it mounts a nested docker-compose setup to launch the **OpenClaw Node Host** (a worker), which registers back to the Host Gateway.
3. **Cloudflare Tunnel**: Securely exposes the node/gateway services over the web without having to expose host firewall ports or manage complex SSL configurations.

Through this structure, tasks sandboxed by the OpenClaw node are executed within a Docker daemon residing securely inside an isolated, containerized Ubuntu environment that is monitored by custom security daemons like Predicate Authority and Mitmproxy.

## Repository Layout

- `compose/`
  The main deployment directory. Contains the primary `docker-compose.yml` for the host, along with `.env` configurations. It also houses `node-docker-compose.yml`, which is safely mounted into the `openclaw-node` service and acts as the setup for the nested, internal worker daemon.
- `node/`
  Contains the Dockerfile, systemd definitions, and `install.sh` needed to build the `openclaw-node` image. This image bundles Docker, Sysbox, Predicate Authority, and Mitmproxy to create the resilient Docker-in-Docker system layer.
- `sandbox/`
  Contains definitions and install scripts for the lightweight execution sandbox images that OpenClaw will use to actually perform tasks securely.
- `scripts/`
  Houses utility scripts relevant to building or lifecycle hooks for the node.
- `setup.sh`
  An interactive setup script that helps bootstrap your `compose/.env` file. It automatically discovers and injects the host's Docker socket GID and generates secure tokens (like `OPENCLAW_GATEWAY_TOKEN`) required for components to communicate.

## Getting Started

1. **Initialize the Environment**:
   Run the setup script from the repository root to populate required variables into `./compose/.env`.

   ```bash
   ./setup.sh
   ```

2. **Launch the Core Infrastructure**:
   Venture into the `compose/` directory to spin up the gateway, secure node, and networking.

   ```bash
   cd compose
   docker compose up -d
   ```

3. **Node Initialization**:
   Behind the scenes, the `openclaw-node` container will boot up, initialize its systemd services (along with the internal Docker daemon), and leverage `node-docker-compose.yml` to launch the worker processes inside its secure boundaries.

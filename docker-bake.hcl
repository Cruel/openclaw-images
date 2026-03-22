variable "IMAGE_PREFIX" {
  default = "ghcr.io/openclaw/openclaw-images"
}

variable "OPENCLAW_VARIANT" {
  default = "slim"
}

variable "OPENCLAW_NODE_IMAGE" {
  default = "node:24-bookworm-slim@sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"
}


# -----------------------------------------------------------------------------
# Groups: These are what we actually build and push
# -----------------------------------------------------------------------------

group "default" {
  targets = ["gateway", "sandbox", "sandbox-browser", "node"]
}

# -----------------------------------------------------------------------------
# Internal Build Targets: Used as bases but NOT pushed to GHCR
# -----------------------------------------------------------------------------

target "sandbox-base" {
  context    = "openclaw"
  dockerfile = "Dockerfile.sandbox"
  platforms  = ["linux/amd64", "linux/arm64"]
}

target "sandbox-custom" {
  context    = "."
  dockerfile = "Dockerfile.sandbox"
  platforms  = ["linux/amd64", "linux/arm64"]
  contexts = {
    "openclaw-sandbox:base" = "target:sandbox-base"
  }
  args = {
    BASE_IMAGE = "openclaw-sandbox:base"
  }
}

# -----------------------------------------------------------------------------
# Public Images: These are pushed to GHCR
# -----------------------------------------------------------------------------

target "gateway" {
  context    = "openclaw"
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  args = {
    OPENCLAW_VARIANT            = "${OPENCLAW_VARIANT}"
    OPENCLAW_INSTALL_DOCKER_CLI = "1"
  }
  tags = ["${IMAGE_PREFIX}/openclaw-gateway:latest"]
}

target "sandbox" {
  context    = "openclaw"
  dockerfile = "Dockerfile.sandbox-common"
  platforms  = ["linux/amd64", "linux/arm64"]
  contexts = {
    "openclaw-sandbox:latest" = "target:sandbox-custom"
  }
  args = {
    BASE_IMAGE = "openclaw-sandbox:latest"
  }
  tags = ["${IMAGE_PREFIX}/openclaw-sandbox:latest"]
}

target "sandbox-browser" {
  context    = "openclaw"
  dockerfile = "Dockerfile.sandbox-browser"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = ["${IMAGE_PREFIX}/openclaw-sandbox-browser:latest"]
}

target "node" {
  context    = "node"
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  args = {
    OPENCLAW_NODE_IMAGE = "${OPENCLAW_NODE_IMAGE}"
  }
  tags       = ["${IMAGE_PREFIX}/openclaw-node:latest"]
}

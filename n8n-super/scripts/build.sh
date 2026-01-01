#!/usr/bin/env bash
# scripts/build.sh
#
# 说明：构建 n8n-super Docker 镜像。
#
# 用法：
#   ./scripts/build.sh
#   ./scripts/build.sh mytag:latest
set -euo pipefail

TAG="${1:-${TAG:-n8n-super:1.78.1}}"

# Optional build args (keep consistent with Dockerfile/docker-compose.yml)
COMMUNITY_NODES_VALUE="${COMMUNITY_NODES:-}"
ARGOCD_VERSION_VALUE="${ARGOCD_VERSION:-}"

# Build-time pip env (for downloading python deps during image build)
PIP_INDEX_URL_VALUE="${PIP_INDEX_URL:-${N8N_PIP_INDEX_URL:-}}"
PIP_EXTRA_INDEX_URL_VALUE="${PIP_EXTRA_INDEX_URL:-${N8N_PIP_EXTRA_INDEX_URL:-}}"
PIP_TRUSTED_HOST_VALUE="${PIP_TRUSTED_HOST:-${N8N_PIP_TRUSTED_HOST:-}}"
PIP_DEFAULT_TIMEOUT_VALUE="${PIP_DEFAULT_TIMEOUT:-${N8N_PIP_DEFAULT_TIMEOUT:-}}"

# 始终以仓库根目录作为构建上下文
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

build_args=()
if [[ -n "$COMMUNITY_NODES_VALUE" ]]; then
  build_args+=(--build-arg "COMMUNITY_NODES=${COMMUNITY_NODES_VALUE}")
fi
if [[ -n "$ARGOCD_VERSION_VALUE" ]]; then
  build_args+=(--build-arg "ARGOCD_VERSION=${ARGOCD_VERSION_VALUE}")
fi

if [[ -n "$PIP_INDEX_URL_VALUE" ]]; then
  build_args+=(--build-arg "PIP_INDEX_URL=${PIP_INDEX_URL_VALUE}")
fi
if [[ -n "$PIP_EXTRA_INDEX_URL_VALUE" ]]; then
  build_args+=(--build-arg "PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL_VALUE}")
fi
if [[ -n "$PIP_TRUSTED_HOST_VALUE" ]]; then
  build_args+=(--build-arg "PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST_VALUE}")
fi
if [[ -n "$PIP_DEFAULT_TIMEOUT_VALUE" ]]; then
  build_args+=(--build-arg "PIP_DEFAULT_TIMEOUT=${PIP_DEFAULT_TIMEOUT_VALUE}")
fi

docker build -t "$TAG" "${build_args[@]}" "$ROOT_DIR"

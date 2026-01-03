#!/usr/bin/env bash
# scripts/build.sh
#
# 说明：构建 n8n-super Docker 镜像（Linux/macOS）。
#
# 用法：
#   ./scripts/build.sh
#   ./scripts/build.sh --tag n8n-super:1.78.1-r1
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

load_build_env() {
  local build_env_file line key val
  build_env_file="$ROOT_DIR/config/build.env"

  if [[ -f "$build_env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" ]] && continue
      [[ "$line" == \#* ]] && continue
      if [[ "$line" == $'\xEF\xBB\xBF'* ]]; then
        line="${line#$'\xEF\xBB\xBF'}"
      fi
      key="${line%%=*}"
      val="${line#*=}"
      key="${key//[[:space:]]/}"
      [[ -z "$key" ]] && continue
      if [[ -z "${!key:-}" ]] && [[ -n "$val" ]]; then
        export "$key=$val"
      fi
    done < "$build_env_file"
  fi
}

TAG="${TAG:-n8n-super:1.78.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./scripts/build.sh [--tag <image:tag>]" >&2
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

load_build_env

COMMUNITY_NODES_VALUE="${COMMUNITY_NODES:-}"
ARGOCD_VERSION_VALUE="${ARGOCD_VERSION:-}"

PIP_INDEX_URL_VALUE="${PIP_INDEX_URL:-${N8N_PIP_INDEX_URL:-}}"
PIP_EXTRA_INDEX_URL_VALUE="${PIP_EXTRA_INDEX_URL:-${N8N_PIP_EXTRA_INDEX_URL:-}}"
PIP_TRUSTED_HOST_VALUE="${PIP_TRUSTED_HOST:-${N8N_PIP_TRUSTED_HOST:-}}"
PIP_DEFAULT_TIMEOUT_VALUE="${PIP_DEFAULT_TIMEOUT:-${N8N_PIP_DEFAULT_TIMEOUT:-}}"

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

#!/usr/bin/env bash
# scripts/run.sh
#
# 说明：单容器模式（docker-compose.yml）的启动脚本。
#
# 用法：
#   ./scripts/run.sh [--no-build] [--no-detach]
set -euo pipefail

BUILD=1
DETACHED=1
PULL=0
FORCE_RECREATE=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/run.sh [--no-build] [--no-detach] [--pull] [--force-recreate]

  --no-build    Do not run "docker compose build" before starting
  --no-detach   Run "docker compose up" in foreground
  --pull        Pull images before starting (for released team tags)
  --force-recreate  Force recreate containers (ensure new image is used)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      BUILD=0
      shift
      ;;
    --no-detach)
      DETACHED=0
      shift
      ;;
    --pull)
      PULL=1
      shift
      ;;
    --force-recreate)
      FORCE_RECREATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

if [[ "$BUILD" -eq 1 ]]; then
  docker compose -f "$COMPOSE_FILE" build
fi

if [[ "$PULL" -eq 1 ]]; then
  docker compose -f "$COMPOSE_FILE" pull
fi

up_args=()
if [[ "$FORCE_RECREATE" -eq 1 ]]; then
  up_args+=(--force-recreate)
fi

if [[ "$DETACHED" -eq 1 ]]; then
  docker compose -f "$COMPOSE_FILE" up -d "${up_args[@]}"
else
  docker compose -f "$COMPOSE_FILE" up "${up_args[@]}"
fi

#!/usr/bin/env bash
# scripts/run.sh
#
# 说明：启动 n8n（单容器或 Queue 模式）。
#
# 用法：
#   ./scripts/run.sh
#   ./scripts/run.sh --queue
#   ./scripts/run.sh --pull --force-recreate
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

QUEUE=0
BUILD=1
DETACHED=1
PULL=0
FORCE_RECREATE=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/run.sh [--queue] [--no-build] [--no-detach] [--pull] [--force-recreate]

  --queue           Use docker-compose-queue.yml
  --no-build        Do not run "docker compose build" before starting
  --no-detach       Run "docker compose up" in foreground
  --pull            Pull images before starting
  --force-recreate  Force recreate containers
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue)
      QUEUE=1
      shift
      ;;
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

load_build_env

COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
if [[ "$QUEUE" -eq 1 ]]; then
  if [[ -f "$ROOT_DIR/docker-compose-queue.yml" ]]; then
    COMPOSE_FILE="$ROOT_DIR/docker-compose-queue.yml"
  else
    COMPOSE_FILE="$ROOT_DIR/docker-compose.queue.yml"
  fi
fi

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

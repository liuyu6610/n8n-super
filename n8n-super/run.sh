#!/usr/bin/env bash
set -euo pipefail

BUILD=1
DETACHED=1

usage() {
  cat <<'USAGE'
Usage: ./run.sh [--no-build] [--no-detach]

  --no-build    Do not run "docker compose build" before starting
  --no-detach   Run "docker compose up" in foreground
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

if [[ "$BUILD" -eq 1 ]]; then
  docker compose -f docker-compose.yml build
fi

if [[ "$DETACHED" -eq 1 ]]; then
  docker compose -f docker-compose.yml up -d
else
  docker compose -f docker-compose.yml up
fi

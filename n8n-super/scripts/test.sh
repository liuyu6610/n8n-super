#!/usr/bin/env bash
# scripts/test.sh
#
# 说明：自检（单容器或 Queue 模式）。
#
# 用法：
#   ./scripts/test.sh
#   ./scripts/test.sh --queue
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

QUEUE=0

usage() {
  echo "Usage: ./scripts/test.sh [--queue]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue)
      QUEUE=1
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

HEALTH_URL="${HEALTH_URL:-http://localhost:5678/healthz}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
ok=0
while [[ $(date +%s) -lt "$deadline" ]]; do
  if curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done

if [[ "$ok" -ne 1 ]]; then
  echo "Health check failed: $HEALTH_URL" >&2
  exit 1
fi

echo "Health check OK: $HEALTH_URL"

if [[ "$QUEUE" -eq 1 ]]; then
  WEB_CONTAINER="${WEB_CONTAINER:-n8n-web}"
  WORKER_CONTAINER="${WORKER_CONTAINER:-n8n-worker}"
  WEBHOOK_CONTAINER="${WEBHOOK_CONTAINER:-n8n-webhook}"

  for c in "$WEB_CONTAINER" "$WORKER_CONTAINER" "$WEBHOOK_CONTAINER"; do
    echo "[check] container=$c"
    docker exec "$c" n8n --version
    docker exec "$c" argocd version --client
    docker exec "$c" /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
  done

  echo "All queue checks passed."
else
  CONTAINER_NAME="${CONTAINER_NAME:-n8n-super}"

  docker exec "$CONTAINER_NAME" n8n --version
  docker exec "$CONTAINER_NAME" argocd version --client
  docker exec "$CONTAINER_NAME" /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
  docker exec "$CONTAINER_NAME" node -e "const p=require('/home/node/.n8n/nodes/node_modules/n8n-nodes-python/package.json'); console.log(p.name+'@'+p.version)"

  echo "All checks passed."
fi

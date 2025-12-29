#!/usr/bin/env bash
# scripts/test-queue.sh
#
# 说明：Queue 模式（docker-compose.queue.yml）的真实自检脚本。
set -euo pipefail

WEB_CONTAINER="${WEB_CONTAINER:-n8n-web}"
WORKER_CONTAINER="${WORKER_CONTAINER:-n8n-worker}"
WEBHOOK_CONTAINER="${WEBHOOK_CONTAINER:-n8n-webhook}"
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

for c in "$WEB_CONTAINER" "$WORKER_CONTAINER" "$WEBHOOK_CONTAINER"; do
  echo "[check] container=$c"
  docker exec "$c" n8n --version
  docker exec "$c" argocd version --client
  docker exec "$c" /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
done

echo "All queue checks passed."

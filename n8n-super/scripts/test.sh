#!/usr/bin/env bash
# scripts/test.sh
#
# 说明：单容器模式（docker-compose.yml）的自检脚本。
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-n8n-super}"
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

docker exec "$CONTAINER_NAME" n8n --version

docker exec "$CONTAINER_NAME" argocd version --client

docker exec "$CONTAINER_NAME" /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"

docker exec "$CONTAINER_NAME" node -e "const p=require('/home/node/.n8n/nodes/node_modules/n8n-nodes-python/package.json'); console.log(p.name+'@'+p.version)"

echo "All checks passed."

#!/usr/bin/env bash
# scripts/build.sh
#
# 说明：构建 n8n-super Docker 镜像。
#
# 用法：
#   ./scripts/build.sh
#   ./scripts/build.sh mytag:latest
set -euo pipefail

TAG="${1:-n8n-super:1.78.1}"

# 始终以仓库根目录作为构建上下文
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

docker build -t "$TAG" "$ROOT_DIR"

#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-n8n-super:1.78.1}"

docker build -t "$TAG" .

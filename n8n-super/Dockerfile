FROM n8nio/n8n:1.78.1

USER root

COPY n8n-python3-wrapper.sh /usr/local/bin/n8n-python3-wrapper.sh

# Install system tooling (works on both Debian/Ubuntu and Alpine based variants)
RUN set -eux; \
  if command -v apt-get >/dev/null 2>&1; then \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      python3 \
      python3-venv \
      python3-pip \
      rsync \
      tar \
      unzip \
      wget \
    ; \
    rm -rf /var/lib/apt/lists/*; \
  elif command -v apk >/dev/null 2>&1; then \
    apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      python3 \
      py3-pip \
      py3-virtualenv \
      rsync \
      tar \
      unzip \
      wget \
    ; \
  else \
    echo "Unsupported base image: missing apt-get/apk" >&2; \
    exit 1; \
  fi

# Python venv for n8n python nodes / Execute Command usage
ENV N8N_PYTHON_VENV=/opt/n8n-python-venv
RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    virtualenv -p python3 "${N8N_PYTHON_VENV}"; \
  else \
    python3 -m venv "${N8N_PYTHON_VENV}"; \
  fi; \
  "${N8N_PYTHON_VENV}/bin/pip" install --no-cache-dir --upgrade pip setuptools wheel; \
  "${N8N_PYTHON_VENV}/bin/pip" install --no-cache-dir python-fire; \
  chmod +x /usr/local/bin/n8n-python3-wrapper.sh; \
  if [ -x "${N8N_PYTHON_VENV}/bin/python3" ] && [ ! -x "${N8N_PYTHON_VENV}/bin/python3-real" ]; then \
    mv "${N8N_PYTHON_VENV}/bin/python3" "${N8N_PYTHON_VENV}/bin/python3-real"; \
    cp /usr/local/bin/n8n-python3-wrapper.sh "${N8N_PYTHON_VENV}/bin/python3"; \
    chmod +x "${N8N_PYTHON_VENV}/bin/python3"; \
  fi; \
  chown -R node:node "${N8N_PYTHON_VENV}"

# Optional: argo cd cli
ARG ARGOCD_VERSION=v2.13.3
RUN set -eux; \
  arch="amd64"; \
  curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${arch}"; \
  chmod +x /usr/local/bin/argocd; \
  /usr/local/bin/argocd version --client || true

# n8n community nodes are loaded from ~/.n8n/custom (and nodes download dir)
# Install community nodes into the built-in custom extension dir for deterministic availability.
RUN set -eux; \
  npm config set fund false; \
  npm config set audit false; \
  npm config set update-notifier false; \
  mkdir -p /home/node/.n8n/nodes; \
  cd /home/node/.n8n/nodes; \
  if [ ! -f package.json ]; then npm init -y; fi; \
  npm install --no-fund --no-audit --omit=dev n8n-nodes-python; \
  mkdir -p /home/node/.n8n/custom; \
  chown -R node:node /home/node/.n8n

# Ensure the venv python is preferred at runtime
ENV PATH="${N8N_PYTHON_VENV}/bin:${PATH}"

# Runtime installer: allow pip packages to be injected via env at container start
COPY --chown=node:node docker-entrypoint-extra.sh /docker-entrypoint-extra.sh
RUN set -eux; \
  sed -i 's/\r$//' /docker-entrypoint-extra.sh; \
  chmod +x /docker-entrypoint-extra.sh

USER node

ENTRYPOINT ["tini", "--", "/docker-entrypoint-extra.sh"]

# Dockerfile（n8n-super 镜像构建文件）
#
# 目标：在官方 n8n 镜像（n8nio/n8n:1.78.1）基础上增强：
# - 内置 Python3 + venv（用于 PythonFunction / Execute Command 场景）
# - 为 python3 加 wrapper：支持“按依赖 hash 的独立 venv 缓存 + 自动 pip install”
# - 预装 argocd CLI（示例：GitOps/发布工作流可直接调用）
# - 预装社区节点 n8n-nodes-python（提供 PythonFunction 节点）
#
# 设计原则：
# - 版本固定、可复现、可运维
# - 尽量兼容 n8n 官方入口逻辑（最终仍走 /docker-entrypoint.sh）
# - 兼容 Alpine / Debian 两类基础镜像（n8nio/n8n 随版本可能变化）
#
# 扩展示例（只示意，不改变当前行为）：
# - 安装更多 CLI：kubectl/helm/terraform 等（建议固定版本并校验）
# - 安装更多社区节点：在 npm install 行追加 n8n-nodes-xxx
# - 安全：生产环境谨慎启用 Command 节点，建议配合隔离与权限控制
FROM n8nio/n8n:1.78.1

# 切到 root：安装系统依赖、写入 /usr/local/bin、创建 venv 等需要 root 权限
USER root

# python3 wrapper：
# - 构建时复制到 /usr/local/bin
# - 后续会把 venv 里的 python3 替换为该 wrapper（并把真实解释器重命名为 python3-real）
# - wrapper 会按环境变量执行“自动装包 + 独立 venv 缓存”（详见 n8n-python3-wrapper.sh）
COPY n8n-python3-wrapper.sh /usr/local/bin/n8n-python3-wrapper.sh

# Install system tooling
#
# 兼容策略：
# - 如果基础镜像带 apt-get：按 Debian/Ubuntu 系列安装
# - 如果基础镜像带 apk：按 Alpine 系列安装
#
# 安装内容说明：
# - bash/curl/git/jq/openssh-client/rsync/tar/unzip/wget：用于工作流命令行与运维工具链
# - python3/python3-venv/python3-pip 或 py3-virtualenv：用于 PythonFunction
#
# 注意：
# - Alpine 下 python3 -m venv 有时依赖包不齐或行为差异，使用 py3-virtualenv 更稳
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
#
# 说明：
# - 这是“基础 venv”，位于 /opt/n8n-python-venv
# - 它提供 python-fire 等基础依赖，并把 python3 替换为 wrapper
# - 业务依赖（requests/pandas 等）不直接装进基础 venv，而是由 wrapper 按 hash 生成独立 venv 缓存
#
# 这样做的好处：
# - 团队多人共用同一 n8n 时，不同 workflow 的依赖不会互相覆盖
# - 相同依赖集合可复用缓存，避免重复下载
ENV N8N_PYTHON_VENV=/opt/n8n-python-venv
RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    virtualenv -p python3 "${N8N_PYTHON_VENV}"; \
  else \
    python3 -m venv "${N8N_PYTHON_VENV}"; \
  fi; \
  # 升级 pip 工具链，避免老版本 pip 的兼容性问题
  "${N8N_PYTHON_VENV}/bin/pip" install --no-cache-dir --upgrade pip setuptools wheel; \
  # PythonFunction 依赖 python-fire（基础必备），安装到基础 venv
  "${N8N_PYTHON_VENV}/bin/pip" install --no-cache-dir python-fire; \
  # 确保 wrapper 可执行
  chmod +x /usr/local/bin/n8n-python3-wrapper.sh; \
  # 将基础 venv 的 python3 重命名为 python3-real，并用 wrapper 替换 python3
  # 这样 n8n-nodes-python 调用 python3 时会自动触发依赖安装逻辑
  if [ -x "${N8N_PYTHON_VENV}/bin/python3" ] && [ ! -x "${N8N_PYTHON_VENV}/bin/python3-real" ]; then \
    mv "${N8N_PYTHON_VENV}/bin/python3" "${N8N_PYTHON_VENV}/bin/python3-real"; \
    cp /usr/local/bin/n8n-python3-wrapper.sh "${N8N_PYTHON_VENV}/bin/python3"; \
    chmod +x "${N8N_PYTHON_VENV}/bin/python3"; \
  fi; \
  # 运行时默认用户是 node，确保 node 用户可读写 venv
  chown -R node:node "${N8N_PYTHON_VENV}"

# Optional: argo cd cli
#
# 说明：
# - 这里直接下载官方 release 二进制到 /usr/local/bin/argocd
# - 建议在企业内网中：使用制品库镜像源 + 固定版本 + 校验 sha256
#
# 扩展示例（只示意）：
# - 你可以在这里再安装 kubectl/helm/terraform 等，并把版本做成 ARG
ARG ARGOCD_VERSION=v2.13.3
RUN set -eux; \
  arch="amd64"; \
  curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${arch}"; \
  chmod +x /usr/local/bin/argocd; \
  /usr/local/bin/argocd version --client || true

# n8n community nodes
#
# 说明：
# - 社区节点是 npm 包（n8n-nodes-xxx），n8n 会从 ~/.n8n/nodes 扫描加载
# - 这里在镜像构建时安装，保证容器首次启动就具备该节点（可复现/可审计）
#
# 扩展示例（只示意）：
# - 追加更多节点：npm install ... n8n-nodes-xxx n8n-nodes-yyy
# - 如果你要固定版本：npm install n8n-nodes-xxx@<version>
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
#
# 说明：
# - 让 /opt/n8n-python-venv/bin 优先于系统 python
# - python3 实际指向 wrapper（会按 hash 创建/复用独立 venv）
ENV PATH="${N8N_PYTHON_VENV}/bin:${PATH}"

# Runtime entrypoint wrapper
#
# 说明：
# - docker-entrypoint-extra.sh 在容器启动时执行：
#   - 加载 config 注入文件（N8N_SUPER_CONFIG_FILE）
#   - 映射 pip 源环境变量
#   - 可选清理 venv 缓存
#   - 最后 exec 官方 /docker-entrypoint.sh（保持 n8n 官方行为）
COPY --chown=node:node docker-entrypoint-extra.sh /docker-entrypoint-extra.sh
RUN set -eux; \
  # 避免脚本在 Windows 编辑后带 CRLF（历史坑）
  sed -i 's/\r$//' /docker-entrypoint-extra.sh; \
  chmod +x /docker-entrypoint-extra.sh

# 运行阶段切回 node：符合 n8n 官方镜像默认用户与安全最佳实践
USER node

# ENTRYPOINT
# - tini 负责处理僵尸进程与信号转发（容器长期运行最佳实践）
# - 由我们的 /docker-entrypoint-extra.sh 包装官方 entrypoint
ENTRYPOINT ["tini", "--", "/docker-entrypoint-extra.sh"]

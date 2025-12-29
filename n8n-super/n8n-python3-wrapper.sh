#!/bin/sh
 # n8n-python3-wrapper.sh
 #
 # 作用：作为 venv 内的 python3“透明代理”，在每次执行 Python 前按需安装依赖。
 #
 # 为什么要这么做：
 # - n8n 的 PythonFunction（n8n-nodes-python）是通过 spawn('python3', ...) 来执行脚本的。
 # - 如果团队多人共用一个 n8n 实例，不同 workflow 依赖不同 Python 包，直接往同一个 venv 里 pip install
 #   会造成版本互相覆盖（不可运维）。
 #
 # 最优解（企业可运维）：按“依赖集合 hash”创建/复用独立 venv。
 # - 每套 requirements/packages/pip 源参数 -> 一个 hash -> 一个独立 venv（互不影响）
 # - 同一 hash 复用同一 venv（缓存）
 # - 可结合 docker-entrypoint-extra.sh 的 TTL 机制对缓存目录做清理
 #
 # 依赖集合 hash 的输入包括：
 # - requirements 文件内容 hash（如设置了 N8N_PYTHON_REQUIREMENTS_FILE 且文件存在）
 # - N8N_PYTHON_PACKAGES
 # - N8N_PYTHON_PIP_EXTRA_ARGS
 # - pip 镜像源相关：PIP_INDEX_URL / PIP_EXTRA_INDEX_URL / PIP_TRUSTED_HOST / PIP_DEFAULT_TIMEOUT
 #
 # 重要兼容点：
 # - PythonFunction 依赖 python-fire。
 # - 镜像构建阶段会在“基础 venv”（/opt/n8n-python-venv）安装 python-fire。
 # - 独立 venv 创建时使用 --system-site-packages 继承基础 venv 的 site-packages，避免缺 fire。
 set -eu
 
 # 兼容 docker exec 场景：
 # - docker-entrypoint-extra.sh 会在容器启动时加载 N8N_SUPER_CONFIG_FILE 并影响 n8n 主进程环境
 # - 但 docker exec 启动的新进程不会继承 entrypoint 动态导出的变量
 # - 因此 wrapper 在每次执行时也尝试加载同一份配置文件，保证行为一致
 CONFIG_FILE="${N8N_SUPER_CONFIG_FILE:-}"
 if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
   tmp_cfg="$(mktemp)"
   sed '1s/^\xEF\xBB\xBF//; s/\r$//' "${CONFIG_FILE}" > "${tmp_cfg}"
   set -a
   . "${tmp_cfg}"
   set +a
   rm -f "${tmp_cfg}"
 fi

 # 基础 venv：镜像构建时创建，提供 python3-real（未包装的真实解释器）与基础依赖。
 BASE_VENV="${N8N_PYTHON_VENV:-/opt/n8n-python-venv}"
 BASE_PIP_BIN="${BASE_VENV}/bin/pip"
 PY_REAL="${BASE_VENV}/bin/python3-real"
 
 # 独立 venv 缓存目录：每个 hash 一个子目录。
 VENV_CACHE_DIR="${N8N_PYTHON_VENV_CACHE_DIR:-/home/node/.n8n/pyenvs}"

AUTO_INSTALL="${N8N_PYTHON_AUTO_INSTALL:-false}"
PIP_EXTRA_ARGS="${N8N_PYTHON_PIP_EXTRA_ARGS:-}"
EXTRA_PACKAGES="${N8N_PYTHON_PACKAGES:-}"
REQUIREMENTS_FILE="${N8N_PYTHON_REQUIREMENTS_FILE:-}"

 # 将 N8N_PIP_* 映射为 pip 标准环境变量（如果用户未显式设置 PIP_*）。
 if [ -n "${N8N_PIP_INDEX_URL:-}" ] && [ -z "${PIP_INDEX_URL:-}" ]; then export PIP_INDEX_URL="${N8N_PIP_INDEX_URL}"; fi
 if [ -n "${N8N_PIP_EXTRA_INDEX_URL:-}" ] && [ -z "${PIP_EXTRA_INDEX_URL:-}" ]; then export PIP_EXTRA_INDEX_URL="${N8N_PIP_EXTRA_INDEX_URL}"; fi
 if [ -n "${N8N_PIP_TRUSTED_HOST:-}" ] && [ -z "${PIP_TRUSTED_HOST:-}" ]; then export PIP_TRUSTED_HOST="${N8N_PIP_TRUSTED_HOST}"; fi
 if [ -n "${N8N_PIP_DEFAULT_TIMEOUT:-}" ] && [ -z "${PIP_DEFAULT_TIMEOUT:-}" ]; then export PIP_DEFAULT_TIMEOUT="${N8N_PIP_DEFAULT_TIMEOUT}"; fi

need_install=false
if [ "${AUTO_INSTALL}" = "true" ] || [ "${AUTO_INSTALL}" = "1" ] || [ "${AUTO_INSTALL}" = "yes" ]; then
  if [ -n "${REQUIREMENTS_FILE}" ] || [ -n "${EXTRA_PACKAGES}" ]; then
    need_install=true
  fi
fi

 # 如果未开启自动安装，直接使用基础 venv 的真实 python 执行。
 if [ "${need_install}" != "true" ]; then
   exec "${PY_REAL}" "$@"
 fi

if [ -z "${VENV_CACHE_DIR}" ]; then
  echo "[n8n-super] ERROR: N8N_PYTHON_VENV_CACHE_DIR is empty" >&2
  exit 1
fi

mkdir -p "${VENV_CACHE_DIR}"

 # requirements 文件内容 hash（文件不存在则为空字符串，仍会参与整体 sig 计算）。
 req_hash=""
 if [ -n "${REQUIREMENTS_FILE}" ] && [ -f "${REQUIREMENTS_FILE}" ]; then
   req_hash="$(sha256sum "${REQUIREMENTS_FILE}" | cut -d" " -f1)"
 fi

sig_input="${req_hash}|${EXTRA_PACKAGES}|${PIP_EXTRA_ARGS}|${PIP_INDEX_URL:-}|${PIP_EXTRA_INDEX_URL:-}|${PIP_TRUSTED_HOST:-}|${PIP_DEFAULT_TIMEOUT:-}"
sig="$(printf %s "${sig_input}" | sha256sum | cut -d" " -f1)"

VENV_DIR="${VENV_CACHE_DIR}/${sig}"
PIP_BIN="${VENV_DIR}/bin/pip"
PY_BIN="${VENV_DIR}/bin/python"

 # 并发锁：避免同一 hash 被多个执行并发创建/安装。
 lockdir="${VENV_CACHE_DIR}/.${sig}.lock"
 stampfile="${VENV_DIR}/.installed.sig"

old_sig=""
if [ -f "${stampfile}" ]; then old_sig="$(cat "${stampfile}" || true)"; fi

if [ "${sig}" != "${old_sig}" ]; then
  while ! mkdir "${lockdir}" 2>/dev/null; do
    sleep 0.2
  done

  cleanup() {
    rmdir "${lockdir}" 2>/dev/null || true
  }
  trap cleanup EXIT INT TERM

  old_sig=""
  if [ -f "${stampfile}" ]; then old_sig="$(cat "${stampfile}" || true)"; fi
  if [ "${sig}" != "${old_sig}" ]; then
    if [ ! -d "${VENV_DIR}" ]; then
      echo "[n8n-super] Creating isolated venv: ${VENV_DIR}"
      "${PY_REAL}" -m venv --system-site-packages "${VENV_DIR}"
    fi

    if [ ! -x "${PIP_BIN}" ]; then
      echo "[n8n-super] ERROR: pip not found in venv: ${PIP_BIN}" >&2
      exit 1
    fi

    "${PIP_BIN}" install --no-cache-dir -U pip setuptools wheel >/dev/null 2>&1 || true

    if [ -n "${REQUIREMENTS_FILE}" ] && [ -f "${REQUIREMENTS_FILE}" ]; then
      # shellcheck disable=SC2086
      "${PIP_BIN}" install --no-cache-dir ${PIP_EXTRA_ARGS} -r "${REQUIREMENTS_FILE}"
    fi
    if [ -n "${EXTRA_PACKAGES}" ]; then
      # shellcheck disable=SC2086
      "${PIP_BIN}" install --no-cache-dir ${PIP_EXTRA_ARGS} ${EXTRA_PACKAGES}
    fi

    echo "${sig}" > "${stampfile}"
  fi

  cleanup
  trap - EXIT INT TERM
fi

exec "${PY_BIN}" "$@"

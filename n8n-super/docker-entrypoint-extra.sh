#!/bin/sh
 # docker-entrypoint-extra.sh
 #
 # 设计目标：
 # - 在不破坏官方 n8n 容器启动流程的前提下，为 n8n-super 增加“可运维能力”。
 # - 支持从配置文件加载环境变量（便于团队统一管理、迁移、回滚）。
 # - 统一映射 pip 源环境变量（N8N_PIP_* -> PIP_*），实现企业内网 pip 加速。
 # - 支持 Python venv 缓存清理（按天 TTL），避免长期运行缓存膨胀。
 #
 # 关键约束：
 # - 本脚本不直接启动 n8n 主进程，最终必须 exec 官方 /docker-entrypoint.sh。
 # - Python 依赖安装策略由 venv python3 wrapper 决定（按依赖 hash 的独立 venv）。
 set -eu

 CONFIG_FILE="${N8N_SUPER_CONFIG_FILE:-}"
 if [ -n "${CONFIG_FILE}" ]; then
	if [ -f "${CONFIG_FILE}" ]; then
		echo "[n8n-super] Loading config file: ${CONFIG_FILE}"
		tmp_cfg="$(mktemp)"
		# Normalize: remove UTF-8 BOM (if any) and CRLF line endings
		# 说明：
		# - 很多团队会在 Windows 上编辑 .env 文件，容易带 BOM/CRLF，直接 source 会报错。
		# - 这里统一做一次兼容性处理。
		sed '1s/^\xEF\xBB\xBF//; s/\r$//' "${CONFIG_FILE}" > "${tmp_cfg}"
		set -a
		. "${tmp_cfg}"
		set +a
		rm -f "${tmp_cfg}"
	else
		echo "[n8n-super] WARNING: config file not found: ${CONFIG_FILE}" >&2
	fi
 fi

 # Pip mirror/env mapping (company internal index acceleration)
 # 说明：
 # - 统一用 N8N_PIP_* 变量表达“企业侧 pip 配置”，并映射为 pip 标准变量。
 # - 这样对 pip / poetry / pip-tools 等更友好，且便于复用。
if [ -n "${N8N_PIP_INDEX_URL:-}" ] && [ -z "${PIP_INDEX_URL:-}" ]; then
	export PIP_INDEX_URL="${N8N_PIP_INDEX_URL}"
fi
if [ -n "${N8N_PIP_EXTRA_INDEX_URL:-}" ] && [ -z "${PIP_EXTRA_INDEX_URL:-}" ]; then
	export PIP_EXTRA_INDEX_URL="${N8N_PIP_EXTRA_INDEX_URL}"
fi
if [ -n "${N8N_PIP_TRUSTED_HOST:-}" ] && [ -z "${PIP_TRUSTED_HOST:-}" ]; then
	export PIP_TRUSTED_HOST="${N8N_PIP_TRUSTED_HOST}"
fi
if [ -n "${N8N_PIP_DEFAULT_TIMEOUT:-}" ] && [ -z "${PIP_DEFAULT_TIMEOUT:-}" ]; then
	export PIP_DEFAULT_TIMEOUT="${N8N_PIP_DEFAULT_TIMEOUT}"
fi

 # 基础 venv：镜像构建时创建（包含 python-fire 等基础依赖）。
 # 注意：运行时“业务依赖”不再直接装入该 venv，避免多人互相覆盖。
 VENV="${N8N_PYTHON_VENV:-/opt/n8n-python-venv}"
 PIP_BIN="${VENV}/bin/pip"
 PY_BIN="${VENV}/bin/python"

 VENV_CACHE_DIR="${N8N_PYTHON_VENV_CACHE_DIR:-/home/node/.n8n/pyenvs}"
 VENV_CACHE_CLEANUP="${N8N_PYTHON_VENV_CACHE_CLEANUP:-}"
 VENV_CACHE_TTL_DAYS="${N8N_PYTHON_VENV_CACHE_TTL_DAYS:-}"

PIP_EXTRA_ARGS="${N8N_PYTHON_PIP_EXTRA_ARGS:-}"
EXTRA_PACKAGES="${N8N_PYTHON_PACKAGES:-}"
REQUIREMENTS_FILE="${N8N_PYTHON_REQUIREMENTS_FILE:-}"
AUTO_INSTALL="${N8N_PYTHON_AUTO_INSTALL:-}"

 # 如果你配置了 requirements/packages，提示用户当前策略。
 # 注意：真正的安装动作在 python3 wrapper 中执行（按依赖 hash 创建独立 venv）。
 if [ -n "${REQUIREMENTS_FILE}" ] || [ -n "${EXTRA_PACKAGES}" ]; then
	echo "[n8n-super] Extra Python packages requested"
	echo "[n8n-super] NOTE: runtime isolated venv mode enabled; python3 wrapper will install per-requirements hash"
	echo "[n8n-super] NOTE: base venv will NOT be modified at container startup"
 fi

if [ -n "${AUTO_INSTALL}" ]; then
	echo "[n8n-super] N8N_PYTHON_AUTO_INSTALL=${AUTO_INSTALL} (python3 wrapper will handle runtime installs)"
fi

 # 可选：缓存清理
 # - 触发时机：容器启动时
 # - 策略：删除 VENV_CACHE_DIR 下 mtime 超过 N 天的一级子目录
 # - 风险：如果正在使用的 venv 目录恰好被判定过期，可能导致运行中失败。
 #   因此建议配合业务场景设置合适的 TTL，或在低峰期重启。
 if [ "${VENV_CACHE_CLEANUP}" = "true" ] || [ "${VENV_CACHE_CLEANUP}" = "1" ] || [ "${VENV_CACHE_CLEANUP}" = "yes" ]; then
	if [ -n "${VENV_CACHE_TTL_DAYS}" ]; then
		if [ -d "${VENV_CACHE_DIR}" ]; then
			echo "[n8n-super] Cleaning venv cache: dir=${VENV_CACHE_DIR} ttl_days=${VENV_CACHE_TTL_DAYS}"
			# Only delete immediate children folders older than ttl days
			find "${VENV_CACHE_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime "+${VENV_CACHE_TTL_DAYS}" -print -exec rm -rf {} \; 2>/dev/null || true
		fi
	else
		echo "[n8n-super] WARNING: N8N_PYTHON_VENV_CACHE_CLEANUP enabled but N8N_PYTHON_VENV_CACHE_TTL_DAYS is empty" >&2
	fi
 fi

exec /docker-entrypoint.sh "$@"

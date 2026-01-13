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

 VENV_BOOTSTRAP="${N8N_PYTHON_VENV_BOOTSTRAP:-}"

 if [ "${VENV_BOOTSTRAP}" = "true" ] || [ "${VENV_BOOTSTRAP}" = "1" ] || [ "${VENV_BOOTSTRAP}" = "yes" ]; then
	if [ -n "${VENV}" ] && [ "${VENV}" != "/opt/n8n-python-venv" ]; then
		if [ ! -x "${VENV}/bin/python" ] && [ ! -x "${VENV}/bin/python3" ]; then
			echo "[n8n-super] Bootstrapping shared python venv into: ${VENV}"
			mkdir -p "${VENV}" || true
			if command -v rsync >/dev/null 2>&1; then
				rsync -a "/opt/n8n-python-venv/" "${VENV}/"
			else
				cp -a "/opt/n8n-python-venv/." "${VENV}/"
			fi
		fi
	fi
 fi

 # 如果你配置了 requirements/packages，提示用户当前策略。
 # 注意：真正的安装动作在 python3 wrapper 中执行（按依赖 hash 创建独立 venv）。
 if [ -n "${REQUIREMENTS_FILE}" ] || [ -n "${EXTRA_PACKAGES}" ]; then
	echo "[n8n-super] Extra Python packages requested"
	echo "[n8n-super] NOTE: single shared venv mode: runtime installs (if enabled) will target N8N_PYTHON_VENV"
 fi

if [ -n "${AUTO_INSTALL}" ]; then
	echo "[n8n-super] N8N_PYTHON_AUTO_INSTALL=${AUTO_INSTALL}"
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

 # Community nodes sync
 #
 # 说明：
 # - docker-compose.yml 通常会把 /home/node/.n8n 挂载成 volume（持久化）
 # - 这会覆盖镜像构建时写入 /home/node/.n8n/nodes 的内容
 # - 因此我们在构建时把预装社区节点备份到 /opt/n8n-super-prebuilt-nodes
 # - 启动时首次同步到 volume 内，保证 UI 能加载到节点
 PREBUILT_DIR="/opt/n8n-super-prebuilt-nodes"
 N8N_NODES_DIR="/home/node/.n8n/nodes"
 SYNC_MARKER="${N8N_NODES_DIR}/.n8n-super-prebuilt-synced"
 if [ -d "${PREBUILT_DIR}" ] && [ -f "${PREBUILT_DIR}/package.json" ]; then
	CUSTOM_DIR="/home/node/.n8n/custom"
	CUSTOM_MARKER="${CUSTOM_DIR}/.n8n-super-prebuilt-synced"
	CUSTOM_PATCH_MARKER="${CUSTOM_DIR}/.n8n-super-prebuilt-patched"
	prebuilt_hash=""
	if command -v sha256sum >/dev/null 2>&1; then
		prebuilt_hash="$(sha256sum "${PREBUILT_DIR}/package.json" | cut -d" " -f1)"
	fi
	mkdir -p "${CUSTOM_DIR}" || true
	old_custom_hash=""
	if [ -f "${CUSTOM_MARKER}" ]; then old_custom_hash="$(cat "${CUSTOM_MARKER}" 2>/dev/null || true)"; fi
	if [ ! -f "${CUSTOM_MARKER}" ] || [ -n "${prebuilt_hash}" ] && [ "${old_custom_hash}" != "${prebuilt_hash}" ]; then
		echo "[n8n-super] Syncing prebuilt community nodes into ${CUSTOM_DIR}"
		if command -v rsync >/dev/null 2>&1; then
			rsync -a --delete "${PREBUILT_DIR}/" "${CUSTOM_DIR}/"
		else
			rm -rf "${CUSTOM_DIR}/node_modules" "${CUSTOM_DIR}/package.json" "${CUSTOM_DIR}/package-lock.json" 2>/dev/null || true
			cp -a "${PREBUILT_DIR}/." "${CUSTOM_DIR}/"
		fi
		if [ -n "${prebuilt_hash}" ]; then
			echo "${prebuilt_hash}" > "${CUSTOM_MARKER}" || true
		else
			touch "${CUSTOM_MARKER}" || true
		fi
	fi

	# Compatibility patch for some community packages
	# - n8n-nodes-dingtalk: node refers to credential name 'dingtalkApi' but credential exported is 'dingTalkApi'
	# - patch dist file in-place (one-time) to keep n8n startup stable and node available in UI
	old_patch_hash=""
	if [ -f "${CUSTOM_PATCH_MARKER}" ]; then old_patch_hash="$(cat "${CUSTOM_PATCH_MARKER}" 2>/dev/null || true)"; fi
	if [ ! -f "${CUSTOM_PATCH_MARKER}" ] || [ -n "${prebuilt_hash}" ] && [ "${old_patch_hash}" != "${prebuilt_hash}" ]; then
		DINGTALK_NODE_JS="${CUSTOM_DIR}/node_modules/n8n-nodes-dingtalk/dist/nodes/DingTalk/DingTalk.node.js"
		if [ -f "${DINGTALK_NODE_JS}" ]; then
			# BusyBox sed does not support \xNN escapes; use literal quotes.
			sed -i "s/name: 'dingtalkApi'/name: 'dingTalkApi'/g" "${DINGTALK_NODE_JS}" || true
			# Repair any previous incorrect patch results like: name: x27dingTalkApix27,
			sed -i "s/name: x27dingtalkApix27/name: 'dingTalkApi'/g" "${DINGTALK_NODE_JS}" || true
			sed -i "s/name: x27dingTalkApix27/name: 'dingTalkApi'/g" "${DINGTALK_NODE_JS}" || true
		fi
		if [ -n "${prebuilt_hash}" ]; then
			echo "${prebuilt_hash}" > "${CUSTOM_PATCH_MARKER}" || true
		else
			touch "${CUSTOM_PATCH_MARKER}" || true
		fi
	fi

	mkdir -p "${N8N_NODES_DIR}" || true
	old_nodes_hash=""
	if [ -f "${SYNC_MARKER}" ]; then old_nodes_hash="$(cat "${SYNC_MARKER}" 2>/dev/null || true)"; fi
	if [ ! -f "${SYNC_MARKER}" ] || [ -n "${prebuilt_hash}" ] && [ "${old_nodes_hash}" != "${prebuilt_hash}" ]; then
		echo "[n8n-super] Syncing prebuilt community nodes into ${N8N_NODES_DIR}"
		if command -v rsync >/dev/null 2>&1; then
			rsync -a --delete "${PREBUILT_DIR}/" "${N8N_NODES_DIR}/"
		else
			rm -rf "${N8N_NODES_DIR}/node_modules" "${N8N_NODES_DIR}/package.json" "${N8N_NODES_DIR}/package-lock.json" 2>/dev/null || true
			cp -a "${PREBUILT_DIR}/." "${N8N_NODES_DIR}/"
		fi
		if [ -n "${prebuilt_hash}" ]; then
			echo "${prebuilt_hash}" > "${SYNC_MARKER}" || true
		else
			touch "${SYNC_MARKER}" || true
		fi
	fi
 fi

exec /docker-entrypoint.sh "$@"

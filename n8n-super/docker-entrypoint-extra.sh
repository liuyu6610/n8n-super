#!/bin/sh
set -eu

CONFIG_FILE="${N8N_SUPER_CONFIG_FILE:-}"
if [ -n "${CONFIG_FILE}" ]; then
	if [ -f "${CONFIG_FILE}" ]; then
		echo "[n8n-super] Loading config file: ${CONFIG_FILE}"
		tmp_cfg="$(mktemp)"
		# Normalize: remove UTF-8 BOM (if any) and CRLF line endings
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

VENV="${N8N_PYTHON_VENV:-/opt/n8n-python-venv}"
PIP_BIN="${VENV}/bin/pip"
PY_BIN="${VENV}/bin/python"

PIP_EXTRA_ARGS="${N8N_PYTHON_PIP_EXTRA_ARGS:-}"
EXTRA_PACKAGES="${N8N_PYTHON_PACKAGES:-}"
REQUIREMENTS_FILE="${N8N_PYTHON_REQUIREMENTS_FILE:-}"
AUTO_INSTALL="${N8N_PYTHON_AUTO_INSTALL:-}"

if [ -n "${REQUIREMENTS_FILE}" ] || [ -n "${EXTRA_PACKAGES}" ]; then
	echo "[n8n-super] Extra Python packages install requested"

	if [ ! -x "${PIP_BIN}" ]; then
		echo "[n8n-super] ERROR: pip not found: ${PIP_BIN}" >&2
		exit 1
	fi

	if [ -n "${REQUIREMENTS_FILE}" ]; then
		if [ -f "${REQUIREMENTS_FILE}" ]; then
			echo "[n8n-super] pip install -r ${REQUIREMENTS_FILE}"
			# shellcheck disable=SC2086
			"${PIP_BIN}" install --no-cache-dir ${PIP_EXTRA_ARGS} -r "${REQUIREMENTS_FILE}"
		else
			echo "[n8n-super] WARNING: requirements file not found: ${REQUIREMENTS_FILE}" >&2
		fi
	fi

	if [ -n "${EXTRA_PACKAGES}" ]; then
		echo "[n8n-super] pip install ${EXTRA_PACKAGES}"
		# shellcheck disable=SC2086
		"${PIP_BIN}" install --no-cache-dir ${PIP_EXTRA_ARGS} ${EXTRA_PACKAGES}
	fi

	"${PY_BIN}" -c 'import sys; print("[n8n-super] python:", sys.version)'
fi

if [ -n "${AUTO_INSTALL}" ]; then
	echo "[n8n-super] N8N_PYTHON_AUTO_INSTALL=${AUTO_INSTALL} (python3 wrapper will handle runtime installs)"
fi

exec /docker-entrypoint.sh "$@"

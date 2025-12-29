#!/bin/sh
set -eu

VENV="${N8N_PYTHON_VENV:-/opt/n8n-python-venv}"
PIP_BIN="${VENV}/bin/pip"
PY_REAL="${VENV}/bin/python3-real"

AUTO_INSTALL="${N8N_PYTHON_AUTO_INSTALL:-false}"
PIP_EXTRA_ARGS="${N8N_PYTHON_PIP_EXTRA_ARGS:-}"
EXTRA_PACKAGES="${N8N_PYTHON_PACKAGES:-}"
REQUIREMENTS_FILE="${N8N_PYTHON_REQUIREMENTS_FILE:-}"

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

if [ "${need_install}" = "true" ]; then
  lockdir="${VENV}/.pip-install.lock"
  stampfile="${VENV}/.pip-install.stamp"

  sig_input="${REQUIREMENTS_FILE}|${EXTRA_PACKAGES}|${PIP_EXTRA_ARGS}|${PIP_INDEX_URL:-}|${PIP_EXTRA_INDEX_URL:-}|${PIP_TRUSTED_HOST:-}|${PIP_DEFAULT_TIMEOUT:-}"
  sig="$(printf %s "${sig_input}" | sha256sum | cut -d" " -f1)"
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
fi

exec "${PY_REAL}" "$@"

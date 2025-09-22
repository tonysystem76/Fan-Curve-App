#!/usr/bin/env bash

set -euo pipefail

REPO_DIR_DEFAULT="/home/system76/system76-power"
REPO_DIR="${1:-$REPO_DIR_DEFAULT}"
BIN_DST="/usr/local/bin/system76-power"
SERVICE_NAME="com.system76.PowerDaemon.service"
DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.d"
DROPIN_FILE="${DROPIN_DIR}/override.conf"

echo "Using system76-power fork at: ${REPO_DIR}"

if [ "${EUID}" -ne 0 ]; then
  echo "This script must run as root. Re-running with sudo..."
  exec sudo --preserve-env=REPO_DIR_DEFAULT -- "$0" "$REPO_DIR"
fi

if [ ! -d "${REPO_DIR}" ]; then
  echo "ERROR: Repo directory not found: ${REPO_DIR}" >&2
  exit 1
fi

echo "Stopping ${SERVICE_NAME} if running..."
systemctl stop "${SERVICE_NAME}" || true

echo "Building fork (release)..."
pushd "${REPO_DIR}" >/dev/null
cargo build --release
popd >/dev/null

if [ ! -f "${REPO_DIR}/target/release/system76-power" ]; then
  echo "ERROR: Built binary not found at ${REPO_DIR}/target/release/system76-power" >&2
  exit 1
fi

echo "Installing forked binary to ${BIN_DST}..."
install -D -m 0755 "${REPO_DIR}/target/release/system76-power" "${BIN_DST}"

echo "Creating systemd override at ${DROPIN_FILE}..."
mkdir -p "${DROPIN_DIR}"
cat > "${DROPIN_FILE}" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/system76-power daemon
EOF

echo "Reloading systemd and enabling service..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true

echo "Holding distro package to prevent overwrite..."
if command -v apt-mark >/dev/null 2>&1; then
  apt-mark hold system76-power >/dev/null 2>&1 || true
fi

echo "Starting ${SERVICE_NAME}..."
systemctl start "${SERVICE_NAME}"
sleep 1
systemctl --no-pager --full status "${SERVICE_NAME}" | sed -n '1,40p' || true

echo
echo "Done. The system is now using your forked system76-power at ${BIN_DST}."
echo "To revert: remove ${DROPIN_FILE}, then run 'systemctl daemon-reload && systemctl restart ${SERVICE_NAME}'."



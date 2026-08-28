#!/usr/bin/env bash
# Provision a running DPEA Raspberry Pi from stock Raspberry Pi OS 64-bit (Trixie).
# Idempotent: safe to re-run. Run with sudo.
#
#   sudo ./provision.sh [--hostname arnav-pi]
#
# Use this when you are NOT flashing the prebuilt image (a one-off Pi, or to
# re-apply config). The prebuilt image already does everything here except the
# per-Pi hostname. It does not install any exhibit's Python deps: each repo owns
# those via `uv sync` (pyproject.toml).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

HOSTNAME_NEW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hostname) HOSTNAME_NEW="$2"; shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

dpea_require_root
dpea_apt_update_upgrade
dpea_install_packages "$HERE/packages.txt"
dpea_enable_interfaces
dpea_config_uart
dpea_install_avahi_5358
dpea_install_uv
dpea_config_eth0

[ -n "$HOSTNAME_NEW" ] && raspi-config nonint do_hostname "$HOSTNAME_NEW"

echo "Provisioned. Reboot to apply UART / interface changes:  sudo reboot"

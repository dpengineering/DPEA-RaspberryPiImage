#!/usr/bin/env bash
# Shared DPEA Raspberry Pi provisioning helpers.
# Sourced by provision.sh to configure a running Pi. The image bakes the same
# choices at build time via customize.sh.
#
# Target: Raspberry Pi OS Trixie, 64-bit (aarch64).
#
# Layering rule:
#   apt / packages.txt   -> NON-Python OS libraries only (SDL2, i2c-tools, ...).
#   uv / pyproject.toml  -> ALL Python packages (kivy, pidev, dpeaDPi, RPi.GPIO,
#                           spidev, smbus2, adafruit-*). apt python3-* do NOT
#                           populate a uv venv, so they never substitute for a dep.

set -euo pipefail

# Expand a packages.txt into a bare list: strip # comments and blank lines.
pkgs_from_file() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"; }

dpea_require_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }; }

dpea_apt_update_upgrade() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
}

dpea_install_packages() {
  # Install every package listed in $1 (a packages.txt).
  # shellcheck disable=SC2046
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $(pkgs_from_file "$1")
}

dpea_enable_interfaces() {
  # I2C, SPI, and the serial *hardware* (not the login console). Needs a recent
  # raspi-config (ships on Raspberry Pi OS). In a build chroot, edit config.txt directly.
  raspi-config nonint do_i2c 0
  raspi-config nonint do_spi 0
  raspi-config nonint do_serial_hw 0
  raspi-config nonint do_serial_cons 1
}

dpea_config_uart() {
  # Point /dev/serial0 at the PL011 UART on GPIO 14/15 (/dev/ttyAMA0) for the DPi bus.
  local cfg="/boot/firmware/config.txt"
  [ -f "$cfg" ] || cfg="/boot/config.txt"
  grep -q '^dtoverlay=disable-bt' "$cfg" || echo 'dtoverlay=disable-bt' >> "$cfg"
  if grep -qs 'Raspberry Pi 5' /proc/device-tree/model; then
    grep -q '^dtparam=uart0_console' "$cfg" || echo 'dtparam=uart0_console' >> "$cfg"
  fi
}

dpea_install_uv() {
  command -v uv >/dev/null 2>&1 || \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
}

# The patched 5358 avahi as a prebuilt arm64 .deb, built by the avahi_0.8 repo's
# CI. That repo is public, so no auth. This downloads at provision time; the Pi
# never needs GitHub at exhibit runtime.
AVAHI_DEB_URL="${AVAHI_DEB_URL:-https://github.com/dpengineering/avahi_0.8/releases/latest/download/avahi-dpea_0.8_arm64.deb}"
dpea_install_avahi_5358() {
  local tmp; tmp="$(mktemp -d)"
  if curl -fLsS "$AVAHI_DEB_URL" -o "$tmp/avahi.deb"; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp/avahi.deb"
    echo 'avahi-daemon hold' | dpkg --set-selections || true
  else
    echo "ERROR: prebuilt 5358 avahi .deb not found at $AVAHI_DEB_URL" >&2
    echo "Check the avahi_0.8 repo's CI / latest Release." >&2
    return 1
  fi
}

# eth0: DHCP for internet when on a real network, PLUS an always-on static for a
# direct laptop-to-Pi cable (laptop = 172.17.21.1). No gateway on the static, so
# it never competes with DHCP/wifi for the default route.
DPEA_ETH_STATIC="${DPEA_ETH_STATIC:-172.17.21.2/22}"
dpea_config_eth0() {
  local con="${1:-Wired connection 1}"
  nmcli connection modify "$con" ipv4.method auto
  nmcli connection modify "$con" +ipv4.addresses "$DPEA_ETH_STATIC"
  nmcli connection modify "$con" ipv4.may-fail yes
}

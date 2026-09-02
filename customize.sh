#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends \
	$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages.txt)

# SPI is deliberately NOT enabled: the DPi computer board uses GPIO7 (SPI0 CE1)
# as a digital input, and the SPI overlay would claim it.
CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt
grep -q '^dtparam=i2c_arm=on'   "$CONFIG" || echo 'dtparam=i2c_arm=on'   >> "$CONFIG"
grep -q '^enable_uart=1'        "$CONFIG" || echo 'enable_uart=1'        >> "$CONFIG"
grep -q '^dtoverlay=disable-bt' "$CONFIG" || echo 'dtoverlay=disable-bt' >> "$CONFIG"
grep -q '^i2c-dev' /etc/modules || echo 'i2c-dev' >> /etc/modules

# The default serial getty competes with the DPi RS485 bus for /dev/serial0.
CMDLINE=/boot/firmware/cmdline.txt
[ -f "$CMDLINE" ] || CMDLINE=/boot/cmdline.txt
[ -f "$CMDLINE" ] && sed -i -E 's/ ?console=(serial0|ttyAMA0|ttyS0),[0-9]+//g' "$CMDLINE"
install -d /etc/systemd/system
ln -sf /dev/null /etc/systemd/system/serial-getty@ttyAMA0.service

AVAHI_DEB_URL="${AVAHI_DEB_URL:-https://github.com/dpengineering/avahi_0.8/releases/latest/download/avahi-dpea_0.8_arm64.deb}"
if curl -fLsS "$AVAHI_DEB_URL" -o /tmp/avahi.deb; then
	# Keep Raspberry Pi OS's modified config to avoid an interactive dpkg prompt.
	apt-get install -y \
		-o Dpkg::Options::=--force-confdef \
		-o Dpkg::Options::=--force-confold \
		/tmp/avahi.deb
	# A dpkg file conflict can leave the package absent even when apt exits 0.
	dpkg -s avahi-dpea >/dev/null 2>&1 \
		|| { echo "ERROR: avahi-dpea did not install (dpkg file conflict / missing Replaces:?)" >&2; exit 1; }
	ldconfig
	apt-mark hold avahi-daemon avahi-dpea >/dev/null 2>&1 || true
	rm -f /tmp/avahi.deb
else
	echo "ERROR: prebuilt 5358 avahi .deb not found at $AVAHI_DEB_URL" >&2
	exit 1
fi

curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

chown root:root /etc/NetworkManager/system-connections/dpea-eth0.nmconnection
chmod 600      /etc/NetworkManager/system-connections/dpea-eth0.nmconnection

apt-get clean
rm -f /tmp/packages.txt

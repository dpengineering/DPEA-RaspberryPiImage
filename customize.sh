#!/bin/bash -e
# DPEA image customizations. Runs INSIDE the mounted image chroot (see build-image.sh),
# and inside the CI validation container (see .github/workflows/validate.yml).
# Expects /tmp/packages.txt already copied in, and the NetworkManager profile
# already placed at /etc/NetworkManager/system-connections/dpea-eth0.nmconnection.

export DEBIAN_FRONTEND=noninteractive

# --- shared non-Python system packages ---
apt-get update
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends \
	$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages.txt)

# --- hardware interfaces (edit config.txt directly) ---
CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt
grep -q '^dtparam=i2c_arm=on'   "$CONFIG" || echo 'dtparam=i2c_arm=on'   >> "$CONFIG"
grep -q '^dtparam=spi=on'       "$CONFIG" || echo 'dtparam=spi=on'       >> "$CONFIG"
grep -q '^enable_uart=1'        "$CONFIG" || echo 'enable_uart=1'        >> "$CONFIG"
grep -q '^dtoverlay=disable-bt' "$CONFIG" || echo 'dtoverlay=disable-bt' >> "$CONFIG"
grep -q '^i2c-dev' /etc/modules || echo 'i2c-dev' >> /etc/modules

# --- patched avahi (mDNS on 5358) from the prebuilt arm64 .deb (avahi_0.8 CI) ---
AVAHI_DEB_URL="${AVAHI_DEB_URL:-https://github.com/dpengineering/avahi_0.8/releases/latest/download/avahi-dpea_0.8_arm64.deb}"
if curl -fLsS "$AVAHI_DEB_URL" -o /tmp/avahi.deb; then
	apt-get install -y /tmp/avahi.deb
	echo 'avahi-daemon hold' | dpkg --set-selections || true
	rm -f /tmp/avahi.deb
else
	echo "ERROR: prebuilt 5358 avahi .deb not found at $AVAHI_DEB_URL" >&2
	exit 1
fi

# --- uv, system-wide ---
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# --- lock down the baked NetworkManager profile ---
chown root:root /etc/NetworkManager/system-connections/dpea-eth0.nmconnection
chmod 600      /etc/NetworkManager/system-connections/dpea-eth0.nmconnection

apt-get clean
rm -f /tmp/packages.txt

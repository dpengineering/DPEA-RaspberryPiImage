#!/bin/bash
# DPEA image customizations. Runs INSIDE the mounted image chroot (see build-image.sh),
# and inside the CI validation container (see .github/workflows/validate.yml).
# Expects /tmp/packages.txt already copied in, and the NetworkManager profile
# already placed at /etc/NetworkManager/system-connections/dpea-eth0.nmconnection.

# Both callers invoke this as `bash customize.sh`, which ignores the shebang's
# flags, so set the strict flags in the body or a failed step is silently skipped.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- shared non-Python system packages ---
apt-get update
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends \
	$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /tmp/packages.txt)

# --- hardware interfaces (edit config.txt directly) ---
# SPI is deliberately NOT enabled: the DPi computer board uses GPIO7 (SPI0 CE1)
# as a digital input (_IN_3_PIN), so an enabled SPI overlay claims that pin and
# the board's GPIO.setup fails with "GPIO busy".
CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt
grep -q '^dtparam=i2c_arm=on'   "$CONFIG" || echo 'dtparam=i2c_arm=on'   >> "$CONFIG"
grep -q '^enable_uart=1'        "$CONFIG" || echo 'enable_uart=1'        >> "$CONFIG"
grep -q '^dtoverlay=disable-bt' "$CONFIG" || echo 'dtoverlay=disable-bt' >> "$CONFIG"
grep -q '^i2c-dev' /etc/modules || echo 'i2c-dev' >> /etc/modules

# --- serial login console OFF (the UART hardware stays on via enable_uart above) ---
# Raspberry Pi OS runs a getty on the serial console by default; it holds
# /dev/serial0 open and fights the DPi RS485 bus (serial.Serial on /dev/serial0),
# giving "device reports readiness to read but returned no data (multiple access
# on port?)". Disable it two ways: drop the console= token from cmdline.txt, and
# mask the serial getty. enable_uart=1 above keeps the UART itself available.
CMDLINE=/boot/firmware/cmdline.txt
[ -f "$CMDLINE" ] || CMDLINE=/boot/cmdline.txt
[ -f "$CMDLINE" ] && sed -i -E 's/ ?console=(serial0|ttyAMA0|ttyS0),[0-9]+//g' "$CMDLINE"
install -d /etc/systemd/system
ln -sf /dev/null /etc/systemd/system/serial-getty@ttyAMA0.service

# --- patched avahi (mDNS on 5358) from the prebuilt arm64 .deb (avahi_0.8 CI) ---
AVAHI_DEB_URL="${AVAHI_DEB_URL:-https://github.com/dpengineering/avahi_0.8/releases/latest/download/avahi-dpea_0.8_arm64.deb}"
if curl -fLsS "$AVAHI_DEB_URL" -o /tmp/avahi.deb; then
	# The .deb Replaces stock avahi and ships /etc/avahi/avahi-daemon.conf as a
	# conffile. The base image's copy is RPi-modified, so dpkg would raise an
	# interactive conffile prompt and abort with "end of file on stdin" in this
	# non-interactive chroot. --force-confold keeps the base config (our 5358 patch
	# is in the binary/lib, not the conf), --force-confdef handles the rest.
	apt-get install -y \
		-o Dpkg::Options::=--force-confdef \
		-o Dpkg::Options::=--force-confold \
		/tmp/avahi.deb
	# The stock RPi OS Desktop base already ships avahi, so the .deb must overwrite
	# its files (it declares Replaces: for them). A dpkg file-overwrite conflict can
	# leave the package uninstalled while apt still exits 0, so assert it is actually
	# present instead of trusting the exit code.
	dpkg -s avahi-dpea >/dev/null 2>&1 \
		|| { echo "ERROR: avahi-dpea did not install (dpkg file conflict / missing Replaces:?)" >&2; exit 1; }
	# Refresh the linker cache so the patched libavahi-core (mDNS on 5358) it just
	# dropped in is the one the daemon loads, not the stock lib it overwrote.
	ldconfig
	# Hold both so an apt upgrade cannot restore the stock 5353 build over ours.
	apt-mark hold avahi-daemon avahi-dpea >/dev/null 2>&1 || true
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

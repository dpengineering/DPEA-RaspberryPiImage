#!/usr/bin/env bash
# Build the DPEA Raspberry Pi OS image by customizing the stock Raspberry Pi OS
# arm64 image: download it, grow it, loop-mount it, run customize.sh in a chroot,
# then recompress.
#
# Invoked by the build-image GitHub Actions workflow (.github/workflows/build-image.yml),
# which runs on a native arm64 runner, so the chroot's arm64 binaries run natively.
# Must run as root (loop-mount + chroot).
#
# Tools: xz-utils parted e2fsprogs curl
#
# PREREQUISITE: the 5358 avahi .deb must be published (avahi_0.8 CI). The chroot
# step hard-fails without it.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/.build}"

# Stock Raspberry Pi OS (arm64, desktop). PIN a dated release for reproducibility;
# check https://downloads.raspberrypi.com/raspios_arm64/images/ for the current one.
BASE_URL="${BASE_URL:-https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2026-06-19/2026-06-18-raspios-trixie-arm64.img.xz}"
GROW_MB="${GROW_MB:-2048}"        # headroom for our added packages
OUT_IMG="$WORK/dpea-pi-$(date +%Y%m%d).img"

[ "$(id -u)" -eq 0 ] || { echo "run as root (loop-mount + chroot)" >&2; exit 1; }
mkdir -p "$WORK"; cd "$WORK"

base_xz="$(basename "$BASE_URL")"; base_img="${base_xz%.xz}"
[ -f "$base_xz" ]  || curl -fL "$BASE_URL" -o "$base_xz"
[ -f "$base_img" ] || xz -dk "$base_xz"
cp -f "$base_img" "$OUT_IMG"

# --- grow the image file + root partition (p2) ---
truncate -s "+${GROW_MB}M" "$OUT_IMG"
LOOP="$(losetup -fP --show "$OUT_IMG")"      # exposes ${LOOP}p1 (boot) + ${LOOP}p2 (root)
cleanup() {
	set +e
	for d in run sys proc dev/pts dev; do umount "$WORK/mnt/$d" 2>/dev/null; done
	umount "$WORK/mnt/boot/firmware" 2>/dev/null
	umount "$WORK/mnt" 2>/dev/null
	losetup -d "$LOOP" 2>/dev/null
}
trap cleanup EXIT
parted -s "$LOOP" resizepart 2 100%
e2fsck -fy "${LOOP}p2" || true
resize2fs "${LOOP}p2"

# --- mount root + boot + pseudo-filesystems ---
MNT="$WORK/mnt"; mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mount "${LOOP}p1" "$MNT/boot/firmware"
for d in dev dev/pts proc sys run; do mount --bind "/$d" "$MNT/$d"; done
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

# --- drop our files in and run the customization ---
install -m 644 "$HERE/packages.txt" "$MNT/tmp/packages.txt"
install -d -m 700 "$MNT/etc/NetworkManager/system-connections"
install -m 600 "$HERE/files/dpea-eth0.nmconnection" \
	"$MNT/etc/NetworkManager/system-connections/dpea-eth0.nmconnection"
install -m 755 "$HERE/customize.sh" "$MNT/tmp/customize.sh"
chroot "$MNT" /bin/bash /tmp/customize.sh
rm -f "$MNT/tmp/customize.sh"

# --- unmount (via trap) + compress ---
cleanup; trap - EXIT

# Record metadata for the Raspberry Pi Imager OS list (os-list.json, built by CI):
# the sha256 + size are of the UNCOMPRESSED image, which Imager verifies.
EXTRACT_SIZE="$(stat -c%s "$OUT_IMG")"
EXTRACT_SHA256="$(sha256sum "$OUT_IMG" | awk '{print $1}')"
xz -T0 -f "$OUT_IMG"
{
	echo "IMG_FILE=$(basename "${OUT_IMG}.xz")"
	echo "EXTRACT_SIZE=${EXTRACT_SIZE}"
	echo "EXTRACT_SHA256=${EXTRACT_SHA256}"
	echo "IMAGE_DOWNLOAD_SIZE=$(stat -c%s "${OUT_IMG}.xz")"
} > "$WORK/image-meta.env"

echo "Image: ${OUT_IMG}.xz"
echo "Meta:  $WORK/image-meta.env"

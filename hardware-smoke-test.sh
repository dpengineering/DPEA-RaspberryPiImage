#!/usr/bin/env bash
# Smoke-test a flashed DPEA Pi. Run ON the Pi after its first boot:
#   sudo ./hardware-smoke-test.sh
# Exits non-zero if any check fails. Covers the things the CI container cannot:
# real device nodes, the serial mapping, live mDNS port, and the eth0 address.

set -u
pass=0; fail=0; skipped=0
chk(){ if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi; }
skip(){ echo "SKIP  $1 ($2)"; skipped=$((skipped+1)); }

chk "uv installed"                "command -v uv"
chk "I2C device node present"     "ls /dev/i2c-*"
chk "SPI device node present"     "ls /dev/spidev*"
chk "/dev/serial0 -> ttyAMA0"     "[ \"\$(readlink -f /dev/serial0)\" = /dev/ttyAMA0 ]"
chk "avahi listening on 5358"     "ss -lun | grep -q ':5358'"
chk "avahi NOT on 5353"           "! ss -lun | grep -q ':5353'"
# The eth0 static (172.17.21.2) only activates when the link has carrier. Running
# this over wifi with no ethernet cable is not an image defect, so SKIP rather than
# FAIL when eth0 has no carrier; plug a cable (or the direct laptop link) and re-run.
if [ "$(cat /sys/class/net/eth0/carrier 2>/dev/null || echo 0)" = 1 ]; then
	chk "eth0 holds 172.17.21.2"  "ip -4 addr show eth0 | grep -q '172.17.21.2'"
else
	skip "eth0 holds 172.17.21.2" "no ethernet carrier; plug a cable and re-run"
fi

echo "----"
echo "$pass passed, $fail failed, $skipped skipped"
echo
echo "Manual direct-cable check: set another machine's ethernet to 172.17.21.1,"
echo "then from it:  ping 172.17.21.2   and   ssh <user>@172.17.21.2"

[ "$fail" -eq 0 ]

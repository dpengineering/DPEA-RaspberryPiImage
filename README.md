# DPEA Raspberry Pi image

Builds the base image every DPEA exhibit Pi runs: Raspberry Pi OS with the
hardware interfaces, the patched mDNS daemon, `uv`, and networking baked in,
published as a GitHub Release. Each exhibit repo then declares its own Python
dependencies and installs them with `uv`.

## What the image bakes in

- **OS**: Raspberry Pi OS Bookworm 64-bit (arm64), Desktop
- **Hardware**: I2C, SPI, and UART enabled. `dtoverlay=disable-bt` so
  `/dev/serial0` is the PL011 UART for the SlushEngine / DPi bus. `i2c-dev` loaded.
- **Networking (`eth0`)**: DHCP for internet, plus an always-on static
  `172.17.21.2/22` for a direct laptop-to-Pi cable.
- **mDNS**: the patched avahi that serves mDNS on port **5358**.
- **Tooling**: `uv`, system-wide.

### Shared apt packages (`packages.txt`)

`packages.txt` is the single source of truth, read by `build-image.sh` and
`provision.sh`. Current contents:

- core: `git`, `curl`, `ca-certificates`
- I2C/SPI: `i2c-tools`
- kivy runtime: `libsdl2-2.0-0`, `libsdl2-image-2.0-0`, `libsdl2-mixer-2.0-0`, `libsdl2-ttf-2.0-0`, `libmtdev1`, `libgl1-mesa-dri`
- mDNS resolution: `libnss-mdns`

Add a package everyone needs by editing `packages.txt`.

## Building the image

### The patched avahi `.deb`

The image installs the 5358 avahi as a prebuilt arm64 `.deb` from
`dpengineering/avahi_0.8`'s latest Release.

### The image build + publish

`.github/workflows/build-image.yml` runs on every image-affecting change to
`main` (`packages.txt`, `customize.sh`, `files/**`, `build-image.sh`) and on
demand, then publishes the result as this repo's latest Release. It runs
`build-image.sh`, which customizes the stock Raspberry Pi OS image: download,
grow, loop-mount, run `customize.sh` in a chroot (packages, avahi, uv, config),
recompress. It runs on a native arm64 runner (free while this repo is public), so
the chroot's arm64 binaries run natively. No default user is baked. Set user +
hostname + wifi in the Imager at flash time. Pin `BASE_URL` in `build-image.sh` to
a specific Raspberry Pi OS release for reproducibility.

## Testing

### In CI, on every PR (`.github/workflows/validate.yml`)

Runs `shellcheck`, then runs `customize.sh` inside an arm64 Bookworm container
and asserts what can be checked without hardware: `uv` present, the 5358 avahi
`.deb` installed, the I2C/SPI/UART lines written, and the eth0 NetworkManager
profile present. This gates merges to `main`.

Container checks cannot exercise real hardware or multicast, so they do not cover
actual I2C/SPI/UART function, live `.local` resolution, or the eth0 address
coming up. Those need a flashed Pi.

### On real hardware (`hardware-smoke-test.sh`)

After flashing a Pi, run `sudo ./hardware-smoke-test.sh` on it. It checks: `uv`
present, `/dev/i2c-*` and `/dev/spidev*` nodes, `/dev/serial0 -> ttyAMA0`, avahi
listening on 5358 (and not 5353), and eth0 holding `172.17.21.2`. For the
direct-cable path, set another machine's ethernet to `172.17.21.1` and confirm
you can reach `172.17.21.2`.

## Files

| File                                | Purpose                                                                      |
|-------------------------------------|------------------------------------------------------------------------------|
| `packages.txt`                      | shared apt package list (single source of truth)                             |
| `build-image.sh`                    | download + grow + loop-mount + chroot-customize the stock image into `.img.xz` |
| `customize.sh`                      | the steps run inside the image chroot                                        |
| `files/dpea-eth0.nmconnection`      | baked NetworkManager profile (eth0 DHCP + static)                            |
| `provision.sh`                      | apply the same config to an already-running Pi (no reflash)                  |
| `lib/common.sh`                     | shared shell helpers for `provision.sh`                                      |
| `hardware-smoke-test.sh`            | on-Pi smoke test of the baked config                                         |
| `.github/workflows/build-image.yml` | build + publish the image                                                    |
| `.github/workflows/validate.yml`    | PR checks (shellcheck + container validation)                                |

The patched avahi `.deb` lives in the `avahi_0.8` repo, not here.

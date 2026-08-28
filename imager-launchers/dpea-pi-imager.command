#!/bin/bash
# macOS: double-click to launch Raspberry Pi Imager preloaded with the DPEA image
# list, so "DPEA Pi" appears in the OS list with the Customisation panel enabled.
exec "/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager" \
  --repo https://github.com/dpengineering/DPEA-RaspberryPiImage/releases/latest/download/os-list.json

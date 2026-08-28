@echo off
rem Windows: double-click to launch Raspberry Pi Imager preloaded with the DPEA
rem image list, so "DPEA Pi" appears with the Customisation panel enabled.
start "" "%ProgramFiles%\Raspberry Pi Imager\rpi-imager.exe" --repo https://github.com/dpengineering/DPEA-RaspberryPiImage/releases/latest/download/os-list.json

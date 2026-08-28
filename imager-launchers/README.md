# Imager launchers

Each launcher opens Raspberry Pi Imager preloaded with the DPEA OS list
(`--repo https://github.com/dpengineering/DPEA-RaspberryPiImage/releases/latest/download/os-list.json`),
so "DPEA Pi" appears in the OS list with the **Customisation** panel enabled
(hostname, SSH, user, wifi). Plain "Use custom" on a local file cannot do that.

- `dpea-pi-imager.command` - macOS (double-click; may need `chmod +x` once, and
  right-click -> Open the first time to clear Gatekeeper).
- `dpea-pi-imager.bat` - Windows (double-click).
- `dpea-pi-imager.desktop` - Linux (mark executable / "Allow launching").

Requires Raspberry Pi Imager installed and internet access. No GitHub account
needed (public repo). These are meant to be handed to students, e.g. from the
student setup repo.

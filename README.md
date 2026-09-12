# Clipboard Bridge for Omarchy

Shared clipboard between Omarchy and the macOS host when Omarchy runs in
Parallels Desktop. Text and images, both directions, paired with one click.

Parallels Tools' clipboard sharing only works with X11. Omarchy runs Hyprland
on Wayland, so copy and paste with the Mac silently does nothing. This plugin
runs the [clipboard-bridge](https://github.com/marcho78/omarchy-clipboard-bridge)
daemon inside omarchy-shell and keeps it alive for as long as the plugin is
enabled.

## Install

In the VM, build and install the daemon as a package, then add the plugin:

```bash
git clone https://github.com/marcho78/omarchy-clipboard-bridge.git
cd omarchy-clipboard-bridge/packaging/aur && makepkg -si
omarchy plugin add https://github.com/marcho78/omarchy-clipboard-bridge-plugin.git --enable
```

The PKGBUILD fetches the tagged source of
[marcho78/omarchy-clipboard-bridge](https://github.com/marcho78/omarchy-clipboard-bridge),
verifies its SHA-256, and compiles it on your machine (a small Rust program,
a couple of minutes; needs `cargo`). The plugin itself never downloads,
verifies or installs anything; it only runs `/usr/bin/clipboard-bridge` if
the package is present.

On the Mac, download the host binary for your CPU from the
[clipboard-bridge releases page](https://github.com/marcho78/omarchy-clipboard-bridge/releases/latest)
(`clipboard-bridge-macos-arm64` for Apple silicon, `clipboard-bridge-macos-x86_64`
for Intel), then in Terminal:

```bash
chmod +x ~/Downloads/clipboard-bridge-macos-arm64
mkdir -p ~/.local/bin && mv ~/Downloads/clipboard-bridge-macos-arm64 ~/.local/bin/clipboard-bridge
~/.local/bin/clipboard-bridge install
```

Checksums are in `SHA256SUMS` on the same release page. If macOS asks whether
`clipboard-bridge` may accept incoming connections, click Allow. Other host
install options are described in the
[clipboard-bridge README](https://github.com/marcho78/omarchy-clipboard-bridge#2-on-the-mac).

Within a few seconds a dialog appears on the Mac with a four-digit pairing
code, and a notification in Omarchy shows the same code. Click **Allow** on
the Mac. Done.

## What the plugin does

* On enable, it checks that `/usr/bin/clipboard-bridge` exists. If not, it
  logs a one-line hint to install the package and checks again every minute.
* It runs `clipboard-bridge connect` as a child of omarchy-shell and restarts
  it with backoff if it exits. Its stderr is read in chunks against a byte
  budget; a flood restarts the daemon instead of reaching the shell.
* The daemon it starts is recorded by pid and kernel start time in
  `$XDG_RUNTIME_DIR`. After a shell restart, the previous daemon is ended only
  if that exact pid still has the recorded start time and command name; no
  process is ever matched by command-line pattern.
* If you already run the daemon through `systemd --user`
  (`systemctl --user enable --now clipboard-bridge`, the unit ships with the
  package), the plugin notices and stays out of the way.
* Disabling or removing the plugin stops the daemon.

Everything runs by absolute path: `/usr/bin/clipboard-bridge`,
`/usr/bin/systemctl`, `/usr/bin/test`, `/usr/bin/kill`. No shell is involved.

IPC:

```bash
omarchy-shell clipboard-bridge status
omarchy-shell clipboard-bridge pair      # forget the pairing and pair again
omarchy-shell clipboard-bridge restart
```

## Remove

```bash
omarchy plugin remove marcho78.clipboard-bridge
sudo pacman -R clipboard-bridge  # optional: the daemon itself
```

To also delete the pairing secrets: `rm -rf ~/.config/clipboard-bridge`.

On the Mac: `clipboard-bridge uninstall --purge` and delete `~/.local/bin/clipboard-bridge`.

## Dependencies

* The `clipboard-bridge` package built from `packaging/aur` in its repo (MIT), which depends on `wl-clipboard`
  (ships with Omarchy) and uses `notify-send` for the pairing notification.

## License

MIT

## Author

[@devsec_ai](https://x.com/devsec_ai) on X

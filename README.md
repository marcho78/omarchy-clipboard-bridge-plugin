# Clipboard Bridge for Omarchy

Shared clipboard between Omarchy and the macOS host when Omarchy runs in
Parallels Desktop. Text and images, both directions, paired with one click.

Parallels Tools' clipboard sharing only works with X11. Omarchy runs Hyprland
on Wayland, so copy and paste with the Mac silently does nothing. This plugin
runs the [clipboard-bridge](https://github.com/marcho78/omarchy-clipboard-bridge)
daemon inside omarchy-shell and keeps it alive for as long as the plugin is
enabled.

## Install

In the VM:

```bash
omarchy plugin add https://github.com/marcho78/omarchy-clipboard-bridge-plugin.git --enable
```

On the Mac, open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/marcho78/omarchy-clipboard-bridge/main/host/install.sh | bash
```

Within a few seconds a dialog appears on the Mac with a four-digit pairing
code, and a notification in Omarchy shows the same code. Click **Allow** on
the Mac. Done.

## What the plugin does

* On enable, it looks for the `clipboard-bridge` binary. If a matching version
  is not already installed (`/usr/bin` or `~/.local/bin`), it downloads the
  pinned release from GitHub into `~/.local/share/clipboard-bridge/bin/` and
  verifies its SHA-256 before running it. Nothing is piped to a shell.
* It then runs `clipboard-bridge connect` as a child of omarchy-shell and
  restarts it with backoff if it exits.
* If you already run the daemon through `systemd --user`, the plugin notices
  and stays out of the way.
* Disabling or removing the plugin stops the daemon.

IPC:

```bash
omarchy-shell ipc call clipboard-bridge status
omarchy-shell ipc call clipboard-bridge pair      # forget the pairing and pair again
omarchy-shell ipc call clipboard-bridge restart
```

## Remove

```bash
omarchy plugin remove marcho78.clipboard-bridge
```

To also delete the downloaded binary and pairing secrets:

```bash
rm -rf ~/.local/share/clipboard-bridge ~/.config/clipboard-bridge
```

On the Mac: `clipboard-bridge uninstall --purge` and delete `~/.local/bin/clipboard-bridge`.

## Dependencies

* `wl-clipboard` (ships with Omarchy)
* `curl`, `sha256sum` (coreutils), `notify-send` for the pairing notification
* The `clipboard-bridge` binary from
  [marcho78/omarchy-clipboard-bridge](https://github.com/marcho78/omarchy-clipboard-bridge)
  (MIT), fetched by version and checksum.

## License

MIT

## Author

[@devsec_ai](https://x.com/devsec_ai) on X

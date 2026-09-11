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

* On enable, it obtains the `clipboard-bridge` binary: a cached copy in
  `~/.local/share/clipboard-bridge/bin/` is reused only if it is owned by you,
  not writable by others, and its SHA-256 matches the digest pinned in
  `bin/ensure-binary.sh`. Otherwise that exact release is downloaded over HTTPS
  with timeouts and a size limit, verified against the same digest, and
  installed atomically. Nothing is executed as part of verification and nothing
  is piped to a shell. All tools are invoked by absolute path.
* It then runs `clipboard-bridge connect` as a child of omarchy-shell and
  restarts it with backoff if it exits.
* If you already run the daemon through `systemd --user`, the plugin notices
  and stays out of the way.
* Disabling or removing the plugin stops the daemon.

IPC:

```bash
omarchy-shell clipboard-bridge status
omarchy-shell clipboard-bridge pair      # forget the pairing and pair again
omarchy-shell clipboard-bridge restart
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

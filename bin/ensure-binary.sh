#!/bin/bash
# Locate or fetch the clipboard-bridge binary and print its path.
#
# Order: an installed binary of the pinned version on PATH or in /usr/bin,
# then a previously fetched copy, then a fresh download of the pinned release
# from GitHub verified against the SHA-256 below. Nothing is piped to a shell.
set -euo pipefail

VERSION="0.2.1"
declare -A SHA256=(
  [aarch64]="43f3179e0d08536622d9f3cbe0fb531bc3dd4595c4db60ca2dd1f2528fe07075"
  [x86_64]="1cfa33c62a294ca47e7e830535d0a83028b5bfe1efcd38e16ff15f12904c882f"
)
REPO="marcho78/omarchy-clipboard-bridge"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/clipboard-bridge/bin"
DEST="$DEST_DIR/clipboard-bridge"

arch="$(uname -m)"
[[ -n "${SHA256[$arch]:-}" ]] || { echo "unsupported architecture: $arch" >&2; exit 1; }

is_pinned() { [[ -x "$1" ]] && [[ "$("$1" --version 2>/dev/null)" == "clipboard-bridge $VERSION" ]]; }

for candidate in /usr/bin/clipboard-bridge "$HOME/.local/bin/clipboard-bridge" "$DEST"; do
  if is_pinned "$candidate"; then
    echo "$candidate"
    exit 0
  fi
done

mkdir -p "$DEST_DIR"
tmp="$(mktemp "$DEST_DIR/.download.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
url="https://github.com/$REPO/releases/download/v$VERSION/clipboard-bridge-linux-$arch"
echo "fetching $url" >&2
curl -fsSL --retry 3 "$url" -o "$tmp"
echo "${SHA256[$arch]}  $tmp" | sha256sum -c --quiet - || { echo "checksum mismatch for $url" >&2; exit 1; }
chmod 755 "$tmp"
mv -f "$tmp" "$DEST"
trap - EXIT
echo "$DEST"

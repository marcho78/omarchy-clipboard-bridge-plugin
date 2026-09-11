#!/usr/bin/bash
# Obtain the clipboard-bridge binary and print its path.
#
# Trust model: the only thing this script trusts is the SHA-256 digest pinned
# below for the exact release version. A cached copy is reused only if it is a
# regular file owned by the current user, not writable by anyone else, and its
# digest matches. Otherwise the release asset is downloaded over HTTPS with
# timeouts and a size ceiling, verified, and installed atomically. Nothing is
# executed as part of verification, and every tool is called by absolute path.
set -euo pipefail

VERSION="0.2.2"
declare -A SHA256=(
  [aarch64]="48a020acb006cc08368eb744da55ddcfbb4def5cb7198a1b0036526dc6938afd"
  [x86_64]="3ff86d464b188412bc7cf0d89e2e0750a8b29db7e036b3ecc46693c632b32a00"
)
REPO="marcho78/omarchy-clipboard-bridge"
MAX_BYTES=16000000
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/clipboard-bridge/bin"
DEST="$DEST_DIR/clipboard-bridge"

fail() { printf 'ensure-binary: %s\n' "$*" >&2; exit 1; }

arch="$(/usr/bin/uname -m)"
expected="${SHA256[$arch]:-}"
[[ -n "$expected" ]] || fail "unsupported architecture: $arch"
uid="$(/usr/bin/id -u)"

# True if $1 is a regular, non-symlink file owned by us, not group/world
# writable, and its SHA-256 equals the pinned digest.
verified() {
  local f="$1" st owner mode sum
  [[ -f "$f" && ! -L "$f" ]] || return 1
  st="$(/usr/bin/stat -c '%u %a' "$f" 2>/dev/null)" || return 1
  owner="${st%% *}"; mode="${st##* }"
  [[ "$owner" == "$uid" ]] || return 1
  (( (8#$mode & 8#022) == 0 )) || return 1
  sum="$(/usr/bin/sha256sum "$f")"; sum="${sum%% *}"
  [[ "$sum" == "$expected" ]]
}

if verified "$DEST"; then
  printf '%s\n' "$DEST"
  exit 0
fi

/usr/bin/mkdir -p "$DEST_DIR"
[[ -d "$DEST_DIR" && ! -L "$DEST_DIR" ]] || fail "$DEST_DIR is not a directory"
[[ "$(/usr/bin/stat -c '%u' "$DEST_DIR")" == "$uid" ]] || fail "$DEST_DIR is not owned by the current user"
/usr/bin/chmod 700 "$DEST_DIR"

tmp="$(/usr/bin/mktemp "$DEST_DIR/.download.XXXXXX")"
trap '/usr/bin/rm -f "$tmp"' EXIT
url="https://github.com/$REPO/releases/download/v$VERSION/clipboard-bridge-linux-$arch"
printf 'fetching %s\n' "$url" >&2
/usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location --max-redirs 5 \
  --connect-timeout 15 --max-time 120 --max-filesize "$MAX_BYTES" --retry 2 \
  --output "$tmp" "$url" || fail "download failed"

size="$(/usr/bin/stat -c '%s' "$tmp")"
(( size > 0 && size <= MAX_BYTES )) || fail "unexpected download size: $size bytes"
sum="$(/usr/bin/sha256sum "$tmp")"; sum="${sum%% *}"
[[ "$sum" == "$expected" ]] || fail "checksum mismatch for $url (got $sum)"

/usr/bin/chmod 755 "$tmp"
/usr/bin/mv -f "$tmp" "$DEST"
trap - EXIT
verified "$DEST" || fail "installed binary failed verification"
printf '%s\n' "$DEST"

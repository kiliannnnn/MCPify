#!/usr/bin/env bash
set -euo pipefail

release_tag="${MCPIFY_RELEASE_TAG:-0.1.0}"
base_url="https://github.com/kiliannnnn/MCPify/releases/download/${release_tag}"

uname_s=$(uname -s)
case "$uname_s" in
  Darwin)
    artifact=mcpify-macos
    ;;
  Linux)
    artifact=mcpify-linux
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    artifact=mcpify-win.exe
    ;;
  *)
    echo "Unsupported OS: $uname_s" >&2
    exit 1
    ;;
 esac

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

download() {
  local url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmpfile"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmpfile" "$url"
  else
    echo "curl or wget is required to download the artifact" >&2
    exit 1
  fi
}

echo "Downloading $artifact from $base_url"
download "$base_url/$artifact"

install_dir="${MCPIFY_INSTALL_DIR:-/usr/local/bin}"
mkdir -p "$install_dir"
install -m 755 "$tmpfile" "$install_dir/mcpify"

echo "Installed mcpify to $install_dir/mcpify"

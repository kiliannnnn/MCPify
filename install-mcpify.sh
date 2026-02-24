#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "Installation failed." >&2' ERR

log() {
  printf "\033[1;34m==>\033[0m %s\n" "$*"
}

fatal() {
  echo "$*" >&2
  exit 1
}

cleanup() {
  rm -f "${checksum_file:-}" "${artifact_file:-}"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fatal "$1 is required"
  fi
}

require_http_client() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi
  fatal "curl or wget is required to download files"
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) echo win ;;
    *) fatal "Unsupported OS: $(uname -s)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    arm64 | aarch64) echo arm64 ;;
    *) fatal "Unsupported architecture: $(uname -m)" ;;
  esac
}

download_to() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    fatal "curl or wget is required to download the artifact"
  fi
}

fetch_to_stdout() {
  local url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO - "$url"
  else
    fatal "curl or wget is required to query GitHub"
  fi
}

hash_verify_cmd=()
if command -v sha256sum >/dev/null 2>&1; then
  hash_verify_cmd=(sha256sum -c -)
elif command -v shasum >/dev/null 2>&1; then
  hash_verify_cmd=(shasum -a 256 -c -)
else
  fatal "sha256sum or shasum is required to verify downloads"
fi

require_cmd uname
require_cmd mktemp
require_cmd printf
require_http_client

force_install=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force_install=1
      ;;
    *)
      fatal "Unknown option: $1"
      ;;
  esac
  shift
done

if [ "$force_install" -eq 0 ] && command -v mcpify >/dev/null 2>&1; then
  log "mcpify already installed at $(command -v mcpify)"
  log "Rerun with --force to reinstall"
  exit 0
fi

release_tag="${MCPIFY_RELEASE_TAG:-latest}"
if [ "$release_tag" = "latest" ]; then
  log "Resolving latest MCPify release"
  release_response=$(fetch_to_stdout "https://api.github.com/repos/kiliannnnn/MCPify/releases/latest")
  case "$release_response" in
    *"API rate limit exceeded"*)
      fatal "GitHub API rate limit exceeded. Set MCPIFY_RELEASE_TAG explicitly."
      ;;
  esac
  release_tag=$(printf '%s' "$release_response" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
  release_tag=${release_tag:-}
  if [ -z "$release_tag" ]; then
    fatal "Unable to determine the latest release tag"
  fi
fi

case "$release_tag" in
  *[!A-Za-z0-9._-]*|"")
    fatal "Invalid release tag: $release_tag"
    ;;
esac

base_url="https://github.com/kiliannnnn/MCPify/releases/download/${release_tag}"
os=$(detect_os)
arch=$(detect_arch)
artifact="mcpify-${os}-${arch}"
if [ "$os" = win ]; then
  artifact+=".exe"
fi

checksum_file=$(mktemp "${TMPDIR:-/tmp}/mcpify-checksums.XXXXXX")
artifact_file=$(mktemp "${TMPDIR:-/tmp}/mcpify.XXXXXX")
trap cleanup EXIT

log "Downloading checksum manifest"
download_to "$base_url/checksums.txt" "$checksum_file"
expected_hash=$(awk -v file="$artifact" '$2 == file {print $1; exit}' "$checksum_file")
if [ -z "$expected_hash" ]; then
  fatal "Checksum not found for $artifact"
fi

log "Downloading $artifact from $base_url"
download_to "$base_url/$artifact" "$artifact_file"

log "Verifying checksum"
printf '%s  %s\n' "$expected_hash" "$artifact_file" | "${hash_verify_cmd[@]}"

log "Installing MCPify ${release_tag} (${os}/${arch})"

install_dir="${MCPIFY_INSTALL_DIR:-/usr/local/bin}"
install_with_sudo=0
run_cmd() {
  if [ "$install_with_sudo" -eq 1 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

ensure_dir() {
  if mkdir -p "$install_dir" >/dev/null 2>&1 && [ -w "$install_dir" ]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    log "Creating $install_dir requires elevated permissions"
    install_with_sudo=1
    run_cmd mkdir -p "$install_dir"
    return 0
  fi

  install_dir="$HOME/.local/bin"
  install_with_sudo=0
  mkdir -p "$install_dir" >/dev/null 2>&1 || fatal "Cannot create $install_dir"
  log "Falling back to $install_dir"
}

ensure_dir

install_target="$install_dir/mcpify"
if [ "$os" = win ]; then
  install_target="$install_dir/mcpify.exe"
fi

install_binary() {
  if command -v install >/dev/null 2>&1; then
    run_cmd install -m 755 "$artifact_file" "$install_target"
  else
    run_cmd cp "$artifact_file" "$install_target"
    run_cmd chmod 755 "$install_target"
  fi
}

install_binary

log "Installed mcpify to $install_target"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    log "Warning: $install_dir is not in your PATH"
    ;;
esac

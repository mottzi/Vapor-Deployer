#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="${DEPLOYER_VERSION:-0.12.0}"
REPOSITORY="${DEPLOYER_REPOSITORY:-mottzi/Vapor-Deployer}"
WORKDIR="${DEPLOYER_BOOTSTRAP_DIR:-/tmp/deployer-${VERSION}}"

info() { printf '==> %s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command '$1'. Install it first, then rerun this script."
}

attach_tty_stdin() {
  [[ -t 0 ]] && return
  [[ -r /dev/tty ]] || die "Interactive setup requires a terminal. Download the script first, then run it from a shell."
  exec </dev/tty
}

asset_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

need curl
need tar

ARCH="$(asset_arch)"
ASSET="deployer-linux-${ARCH}.tar.gz"
URL="https://github.com/${REPOSITORY}/releases/download/${VERSION}/${ASSET}"

info "Preparing ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

info "Downloading ${URL}"
curl -fL -o "${ASSET}" "${URL}"

info "Extracting ${ASSET}"
tar -xzf "${ASSET}"

[[ -x ./deployer ]] || chmod +x ./deployer

info "Starting deployer setup"
attach_tty_stdin
if [[ "${EUID}" -eq 0 ]]; then
  DEPLOYER_RELEASE_TAG="${VERSION}" exec ./deployer setup
else
  need sudo
  exec sudo env DEPLOYER_RELEASE_TAG="${VERSION}" ./deployer setup
fi

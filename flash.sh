#!/usr/bin/env bash
# Copyright (C) 2024 Jared Allard <jaredallard@users.noreply.github.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -e -o pipefail

UBUNTU_VERSION="24.04"
# https://keyserver.ubuntu.com/pks/lookup?search=843938DF228D22F7B3742BC0D94AA3F0EFE21092&fingerprint=on&op=index
GPG_KEY="843938DF228D22F7B3742BC0D94AA3F0EFE21092"

DOWNLOAD_BASE="https://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release"
DOWNLOAD_FILE_NAME="ubuntu-${UBUNTU_VERSION}-preinstalled-server-arm64+raspi.img.xz"
DOWNLOAD_URL="${DOWNLOAD_BASE}/${DOWNLOAD_FILE_NAME}"
UNCOMPRESSED_FILE_NAME="${DOWNLOAD_FILE_NAME%.*}"

out() {
  color="${1:-"36"}"
  prefix="${2:-">"}"
  shift
  shift
  echo -e " \033[${color}m${prefix}\033[0m\033[1m " "$@" "\033[0m"
}

info() {
  out "" "" "$@"
}

success() {
  out 32 "" "$@"
}

error() {
  out 31 "x" "$@"
}

if ! command -v aria2c >/dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    info "Installing 'aria2' via Homebrew..."
    brew install aria2
  else
    error "Please install aria2"
    exit 1
  fi
fi

if ! command -v pv >/dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    info "Installing 'pv' via Homebrew..."
    brew install pv
  else
    error "Please install pv"
    exit 1
  fi
fi

if ! command -v gpg >/dev/null; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    info "Installing 'gpg' via Homebrew..."
    brew install gpg
  else
    error "Please install gpg"
    exit 1
  fi
fi

if ! command -v balena >/dev/null; then
  error "Please ensure asdf or mise is installed and have ran the relevant setup"
  exit 1
fi

if [[ ! -e "$DOWNLOAD_FILE_NAME" ]]; then
  info "Downloading Ubuntu ${UBUNTU_VERSION}... (URL: ${DOWNLOAD_URL})"
  aria2c --console-log-level=error --download-result=hide --file-allocation=none -x 4 "$DOWNLOAD_URL"
  echo # newlines because aria2c (buggily?) doesn't print one
fi

if [[ ! -e "$UNCOMPRESSED_FILE_NAME" ]]; then
  info "Checking validity of image download ..."
  curl --silent -L "$DOWNLOAD_BASE/SHA256SUMS" -o SHA256SUMS
  curl --silent -L "$DOWNLOAD_BASE/SHA256SUMS.gpg" -o SHA256SUMS.gpg

  if ! gpg --list-keys "$GPG_KEY" >/dev/null; then
    info "Fetching GPG key ..."
    gpg --keyserver keyserver.ubuntu.com --recv-keys "$GPG_KEY"
  fi

  gpg --verify SHA256SUMS.gpg SHA256SUMS
  grep "$DOWNLOAD_FILE_NAME" SHA256SUMS | sha256sum -c
  success "Image is valid"

  info "Decompressing image ..."
  pv "$DOWNLOAD_FILE_NAME" | xz -d -T "$(nproc)" --stdout >"$UNCOMPRESSED_FILE_NAME"
  success "Decompressed image successfully"
fi

info "Ensuring valid 1Password CLI session"
if ! op account get >/dev/null; then
  error "Please login to 1Password CLI"
  exit 1
fi

info "Rendering cloud-init ..."
cloudInitTmpFile="$(mktemp)"
trap 'rm -f "$cloudInitTmpFile"' EXIT

# HACK: There's a better way to do this with JQ... I just haven't tried
# hard enough yet.
export PUBLIC_SSH_KEY=$(op item list --tags current-rgst-ssh-key --format json | op item get - --format json | jq -r '(.fields[] | select(.id == "public_key").value), .title' | tr '\n' ' ' | sed 's/ $//')

go run github.com/hairyhenderson/gomplate/v4/cmd/gomplate@v4.0.0-pre-1 -f cloud-init.yaml -o "$cloudInitTmpFile"

info "Getting sudo access"
sudo true

DISK=${DISK:-""}
if [[ -z "$DISK" ]]; then
  DISK="$(diskutil list | grep -v "disk0" | grep "physical" | head -n1 | awk '{ print $1 }' | sed 's_/dev/__' || true)"
  if [[ -z "$DISK" ]]; then
    error "Failed to find a disk, supply it with the DISK environment variable"
    exit 1
  fi
fi

info "Going to flash '$DISK' (r$DISK) in 10s ... (^C to cancel)"
diskutil list "$DISK"
for i in {10..1}; do
  echo -n "$i "
  sleep 1
done
echo ""

success "Flashing ..."
sudo diskutil umountDisk /dev/"$DISK" || true
sudo balena local flash --yes --drive /dev/"$DISK" "$UNCOMPRESSED_FILE_NAME"

info "Setting up cloud-init ..."
sudo diskutil mountDisk /dev/"$DISK"

cp -v "$cloudInitTmpFile" /Volumes/system-boot/user-data

info "Ejecting disk ..."
sudo diskutil umountDisk /dev/"$DISK"
sudo diskutil eject /dev/r"$DISK"

success "Successfully flashed disk $DISK"

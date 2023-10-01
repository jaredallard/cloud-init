#!/usr/bin/env bash
# Automatically provision a new node.
set -e -o pipefail

UBUNTU_VERSION="22.04.3"
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

if ! command -v balena >/dev/null; then
  if ! command -v npm >/dev/null; then
    error "Please install npm"
    exit 1
  fi

  info "Installing 'balena-cli' via npm..."
  npm install -g balena-cli
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
  #gpg --keyserver keyserver.ubuntu.com --recv-keys "$GPG_KEY"
  gpg --verify SHA256SUMS.gpg SHA256SUMS
  grep "$DOWNLOAD_FILE_NAME" SHA256SUMS | sha256sum -c
  success "Image is valid"

  info "Decompressing image ..."
  pv "$DOWNLOAD_FILE_NAME" | xz -d -T "$(nproc)" --stdout >"$UNCOMPRESSED_FILE_NAME"
  success "Decompressed image successfully"
fi

info "Getting sudo access"
sudo true

DISK=${DISK:-""}
if [[ -z "$DISK" ]]; then
  DISK="$(diskutil list | grep -v "disk0" | grep "physical" | head -n1 | awk '{ print $1 }' | sed 's_/dev/__')"
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
cp cloud-init.yaml /Volumes/system-boot/user-data

info "Ejecting disk ..."
sudo diskutil umountDisk /dev/"$DISK"
sudo diskutil eject /dev/r"$DISK"

success "Successfully flashed disk $DISK"

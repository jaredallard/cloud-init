#!/usr/bin/env bash
# Connects to Doppler to fetch credentials and then
# starts microk8s.
set -e

CONFIG_DIR="/etc/rgst"

if [[ -e "$CONFIG_DIR/startup-ran" ]]; then
  echo "startup already ran, skipping"
  exit 0
fi

if [[ -z "${DOPPLER_TOKEN}" ]]; then
  echo "Error: DOPPLER_TOKEN not set, cannot continue" >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"

if ! command -v microk8s >/dev/null; then
  echo "Installing microk8s..."
  snap install microk8s --classic
fi

if ! command -v doppler >/dev/null; then
  echo "Installing doppler..."
  sudo apt install -y curl gnupg
  curl -sSL https://cli.doppler.com/install.sh | bash
fi

TAILSCALE_AUTH_KEY="$(doppler secrets get --plain TAILSCALE_AUTH_KEY)"
if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
  echo "Error: TAILSCALE_AUTH_KEY not set, cannot continue" >&2
  exit 1
fi

echo "Setting up Tailscale..."
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | bash
  sudo apt-get update
  sudo apt-get install tailscale
fi
tailscale up --auth-key="${TAILSCALE_AUTH_KEY}"

MICROK8S_TOKEN=$(doppler secrets get --plain MICROK8S_TOKEN)
if [[ -z "$MICROK8S_TOKEN" ]]; then
  echo "Error: MICROK8S_TOKEN not set, cannot continue" >&2
  exit 1
fi

MICROK8S_LEADER_ADDRESS=$(doppler secrets get --plain MICROK8S_LEADER_ADDRESS)
if [[ -z "$MICROK8S_LEADER_ADDRESS" ]]; then
  echo "Error: MICROK8S_LEADER_ADDRESS not set, cannot continue" >&2
  exit 1
fi

echo "Configuring microk8s..."
TAILSCALE_IP=$(tailscale ip | grep 100 | head -n1)
echo " -> tailscale ip: $TAILSCALE_IP"
sudo sed -i "1s/^/# tailscale0\n--node-ip=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kubelet
sudo sed -i "1s/^/# tailscale0\n--bind-address=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kube-proxy

echo "Joining microk8s cluster..."
microk8s join "$MICROK8S_LEADER_ADDRESS/$MICROK8S_TOKEN" --worker

echo "Finished at $(date)"
touch "$CONFIG_DIR/startup-ran"

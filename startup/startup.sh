#!/usr/bin/env bash
# Connects to Doppler to fetch credentials and then
# starts microk8s.
set -e

# HOME is required to be set by doppler, so here we are.
export HOME=/root

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

echo "Installing the GCP Ops Agent"
curl -fsSl https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh | bash -s -- --also-install

if ! command -v microk8s >/dev/null; then
  echo "Installing microk8s..."
  snap install microk8s --classic
fi

if ! command -v kubectl >/dev/null; then
  echo "Installing kubectl..."
  snap install kubectl --classic
fi

if ! command -v doppler >/dev/null; then
  echo "Installing doppler..."
  apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
  curl -sLf --retry 3 --tlsv1.2 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' | apt-key add -
  echo "deb https://packages.doppler.com/public/cli/deb/debian any-version main" | tee /etc/apt/sources.list.d/doppler-cli.list
  apt-get update
  apt-get install -y doppler
fi

TAILSCALE_AUTH_KEY="$(doppler secrets get --plain TAILSCALE_AUTH_KEY)"
if [[ -z "$TAILSCALE_AUTH_KEY" ]]; then
  echo "Error: TAILSCALE_AUTH_KEY not set, cannot continue" >&2
  exit 1
fi

echo "Setting up Tailscale..."
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | bash
  apt-get update
  apt-get install tailscale
fi
if ! tailscale status >/dev/null 2>&1; then
  tailscale up --auth-key="${TAILSCALE_AUTH_KEY}"
fi

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
if ! grep -q "tailscale0" /var/snap/microk8s/current/args/kubelet; then
  sed -i "1s/^/# tailscale0\n--node-ip=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kubelet
fi
if ! grep -q "tailscale0" /var/snap/microk8s/current/args/kube-proxy; then
  sed -i "1s/^/# tailscale0\n--bind-address=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kube-proxy
fi

## GCP SPECIFIC HERE ##
echo " -> Configuring GCP Support"
projectID="$(curl --retry 3 -s -w "\n" -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)"
region="$(curl --retry 3 -s -w "\n" -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)"
providerID="gce://$projectID/$region/$(hostname)"
echo "  ...> Provider ID: $providerID"
if ! grep -q "gcp" /var/snap/microk8s/current/args/kube-apiserver; then
  sed -i "1s/^/# gcp\n--cloud-provider=gce\n\n/" /var/snap/microk8s/current/args/kube-apiserver
fi
if ! grep -q "gcp" /var/snap/microk8s/current/args/kubelet; then
  sed -i "1s/^/# gcp\n--cloud-provider=gce\n--provider-id=$providerID\n\n/" /var/snap/microk8s/current/args/kubelet
fi
if ! grep -q "gcp" /var/snap/microk8s/current/args/kube-controller-manager; then
  sed -i "1s/^/# gcp\n--cloud-provider=gce\n\n/" /var/snap/microk8s/current/args/kube-controller-manager
fi
##

# Ensure that a "worker" user has access to run
# microk8s commands for manual debugging, but only
# if the worker user exists.
if id -u worker >/dev/null 2>&1; then
  usermod -a -G microk8s worker
  mkdir -p "/home/worker/.kube"
  chown -f -R worker "/home/worker/.kube"
fi

# We have a script that updates /etc/host on the leader
echo "Waiting a few minutes for leader node to see us ..."
sleep 60

echo "Joining microk8s cluster..."
microk8s join "$MICROK8S_LEADER_ADDRESS/$MICROK8S_TOKEN" --worker

KUBECONFIG_FILE=$(doppler secrets get --plain KUBECONFIG_FILE)
if [[ -z "$KUBECONFIG_FILE" ]]; then
  echo "Error: KUBECONFIG_FILE not set, cannot continue" >&2
  exit 1
fi

kubeconfig=$(mktemp)
trap 'rm -f $kubeconfig' EXIT
base64 -d <<<"$KUBECONFIG_FILE" >"$kubeconfig"

echo "Waiting for node to be registered in Kubernetes..."
while ! kubectl --kubeconfig "$kubeconfig" get node "$(hostname)" >/dev/null 2>&1; do
  sleep 1
done

echo "Applying node labels and taints..."
kubectl --kubeconfig "$kubeconfig" label node "$(hostname)" rgst.io/cloud=gcp
kubectl --kubeconfig "$kubeconfig" taint node "$(hostname)" rgst.io/cloud=true:NoSchedule
kubectl --kubeconfig "$kubeconfig" patch node "$(hostname)" --patch '{"spec":{"providerID":"'"$providerID"'"}}'

echo "Finished at $(date)"
touch "$CONFIG_DIR/startup-ran"

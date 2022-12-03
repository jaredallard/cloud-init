#!/usr/bin/env bash
# Removes a node from microk8s on termination.
set -e

KUBECONFIG_FILE=$(doppler secrets get --plain KUBECONFIG_FILE)
if [[ -z "$KUBECONFIG_FILE" ]]; then
  echo "Error: KUBECONFIG_FILE not set, cannot continue" >&2
  exit 1
fi

tmpFile=$(mktemp)
cat >"$tmpFile" <<<"$KUBECONFIG_FILE"

kubectl --kubeconfig "$tmpFile" delete node "$(hostname)"
tailscale logout

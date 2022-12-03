#!/usr/bin/env bash
# This script generates a script to be pasted into a
# cloud-init or other automation script (e.g. GCP).
set -e

echo -n "Doppler token: "
read -r DOPPLER_TOKEN

echo -n "Action (startup or shutdown): "
read -r ACTION

if [[ "$ACTION" != "startup" ]] && [[ "$ACTION" != "shutdown" ]]; then
  echo "Error: invalid action '$ACTION'" >&2
  exit 1
fi

cat startup/bootstrap.sh | sed "s/{{ .DopplerToken }}/${DOPPLER_TOKEN}/g" | sed 's/{{ .Action }}/'"$ACTION"'/g' | pbcopy

echo "Copied bootstrap script to clipboard"

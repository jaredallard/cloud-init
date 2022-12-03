#!/usr/bin/env bash
# This script generates a script to be pasted into a
# cloud-init or other automation script (e.g. GCP).
set -e

echo -n "Doppler token: "
read -r DOPPLER_TOKEN

cat startup/bootstrap.sh | sed "s/{{ .DopplerToken }}/${DOPPLER_TOKEN}/g" | pbcopy
cat startup/bootstrap.sh | sed "s/{{ .DopplerToken }}/${DOPPLER_TOKEN}/g" | bat -P -l bash

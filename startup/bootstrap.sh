#!/usr/bin/env bash
# Bootstrap script to pull the latest version of the
# startup or shutdown script.

# DOPPLER_TOKEN is the token to use when accessing
# Doppler's API.
DOPPLER_TOKEN="{{ .DopplerToken }}"
export DOPPLER_TOKEN

# The URL to the latest version of any of the supported action scripts.
# This should be a raw URL to the script.
SCRIPT_SCRIPT_URL="https://raw.githubusercontent.com/rgst-io/cloud-init/main/startup/{{ .Action }}.sh"

echo "Fetching latest {{ .Action }} script from '${SCRIPT_SCRIPT_URL}' and executing"
curl --connect-timeout 3 --retry 10 --retry-delay 5 -sSL "${SCRIPT_SCRIPT_URL}" | bash

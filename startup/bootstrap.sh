#!/usr/bin/env bash
# Bootstrap script to pull the latest version of the
# startup script.

# DOPPLER_TOKEN is the token to use when accessing
# Doppler's API.
DOPPLER_TOKEN="{{ .DopplerToken }}"
export DOPPLER_TOKEN

# The URL to the latest version of the startup script.
# This should be a raw URL to the script.
STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/rgst-io/cloud-init/main/startup/startup.sh"

echo "Fetching latest start script from '${STARTUP_SCRIPT_URL}' and executing"
curl -sSL "${STARTUP_SCRIPT_URL}" | bash

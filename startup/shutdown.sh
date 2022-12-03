#!/usr/bin/env bash
# Removes a node from microk8s on termination.
set -e

sudo microk8s kubectl delete node "$(hostname)"
tailscale logout

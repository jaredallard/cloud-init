#!/usr/bin/env bash
# Automatically provision a new node.

disk="$(diskutil list | grep 32.0 | awk '{ print $5 }')"

echo "Going to flash '$disk' (r$disk) in 10s ..."
sleep 10

echo "Unmounting disk ..."
sudo diskutil unmountDisk /dev/"$disk"

echo "Starting write ..."
pv ubuntu.img | sudo dd bs=1m of=/dev/r"$disk"
sync

echo "Setting up cloud-init ..."
sudo diskutil mountDisk /dev/disk2
cp cloud-init.yaml /Volumes/system-boot/user-data

mkdir -p /Volumes/system-boot/registrar

echo -n "Should this be a server node? [Y/n]: "
read -r prompt
if [[ $prompt =~ ^(Y|y) ]]; then
  echo "true" >/Volumes/system-boot/registrar/leader
else
  echo "Setting up agent"

  token=$(kubectl get secret -n registrar registrard -ogo-template='{{ .data.REGISTRARD_TOKEN | base64decode }}')
  echo "${token}" >/Volumes/system-boot/registrar/token
fi

echo "Ejecting disk ..."
sudo diskutil umountDisk /dev/disk2
sudo diskutil eject /dev/r"$disk"

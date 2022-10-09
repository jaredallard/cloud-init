#!/usr/bin/env bash
# Migrates an older node to the new cloud-init.yaml

# Add br_netfilter to the kernel modules to load
echo 'br_netfilter' | sudo tee -a /etc/modules

# Enable cgroup_memory and cgroups v1
echo "console=serial0,115200 dwc_otg.lpm_enable=0 console=tty1 root=LABEL=writable rootfstype=ext4 rootwait fixrtc quiet splash cgroup_enable=memory cgroup_memory=1 systemd.unified_cgroup_hierarchy=0" | sudo tee /boot/firmware/cmdline.txt

# Allow IP forwarding
sudo ufw default allow forward

# Install snapd and microk8s
sudo apt install -y snapd
sudo snap install microk8s --classic

# Allow access to microk8s
sudo usermod -a -G microk8s worker
sudo chown -f -R worker ~/.kube

# Set the node-ip
TAILSCALE_IP=$(tailscale ip | grep 100 | head -n1)
sudo sed -i "1s/^/# tailscale0\n--node-ip=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kubelet
sudo sed -i "1s/^/# tailscale0\n--bind-address=${TAILSCALE_IP}\n\n/" /var/snap/microk8s/current/args/kube-proxy

# Reboot the node
sudo reboot

# After reboot, join the cluster
microk8s join command from the leader node

## Note: sometimes need to do this
sudo snap stop microk8s
sudo snap start microk8s

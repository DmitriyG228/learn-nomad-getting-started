#!/bin/bash
set -e

echo "Installing CNI plugins on client nodes..."

# List of client node IPs
CLIENT_IPS=(
    "173.199.118.40"   # vexa-client-static-1
    "207.246.95.118"   # vexa-client-static-2
    "173.199.126.49"   # vexa-client-workload-1
    "45.63.1.200"      # vexa-client-workload-2
    "173.199.119.57"   # vexa-client-workload-3
    "173.199.122.237"  # vexa-client-gpu-1
)

for ip in "${CLIENT_IPS[@]}"; do
    echo "Installing CNI plugins on $ip..."
    ssh -o StrictHostKeyChecking=no -i ssh-key-vexa-prod.pem root@$ip << 'REMOTE_SCRIPT'
        # Install CNI plugins
        CNI_VERSION="1.3.0"
        mkdir -p /opt/cni/bin
        cd /tmp
        curl -sSL https://github.com/containernetworking/plugins/releases/download/v$\{CNI_VERSION\}/cni-plugins-linux-amd64-v$\{CNI_VERSION\}.tgz -o cni-plugins.tgz
        tar -C /opt/cni/bin -xzf cni-plugins.tgz
        chmod +x /opt/cni/bin/*
        rm cni-plugins.tgz
        
        # Create CNI configuration directory
        mkdir -p /etc/cni/net.d
        
        echo "CNI plugins installed, restarting Nomad..."
        systemctl restart nomad
        sleep 10
        echo "Nomad restarted on $(hostname)"
REMOTE_SCRIPT
    echo "Completed installation on $ip"
done

echo "CNI installation completed on all client nodes!"

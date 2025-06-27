#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/startup-script.log) 2>&1

echo "Starting Nomad client setup with auto-discovery..."
date

# Update system and install dependencies
apt-get update
apt-get install -y curl unzip jq netcat-traditional docker.io

# Start Docker
systemctl enable docker
systemctl start docker

# Install CNI plugins (required for bridge networking)
echo "Installing CNI plugins..."
export ARCH_CNI=$( [ $(uname -m) = aarch64 ] && echo arm64 || echo amd64)
export CNI_PLUGIN_VERSION=v1.6.2
curl -L -o cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-${ARCH_CNI}-${CNI_PLUGIN_VERSION}.tgz"
mkdir -p /opt/cni/bin
tar -C /opt/cni/bin -xzf cni-plugins.tgz
rm cni-plugins.tgz

# Load bridge module and configure bridge networking
echo "Configuring bridge networking..."
modprobe bridge
echo 1 > /proc/sys/net/bridge/bridge-nf-call-arptables
echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables  
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

# Make bridge networking settings persistent
cat > /etc/sysctl.d/bridge.conf <<EOF
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Create CNI config directory
mkdir -p /opt/cni/config

# Install Nomad
cd /tmp
curl -fsSL https://releases.hashicorp.com/nomad/1.8.0/nomad_1.8.0_linux_amd64.zip -o nomad.zip
unzip nomad.zip
mv nomad /usr/local/bin/
chmod +x /usr/local/bin/nomad

# Create nomad user and directories
useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
mkdir -p /opt/nomad /etc/nomad.d /opt/alloc_mounts
# Keep nomad user ownership for data directories but allow root access
chown -R nomad:nomad /opt/nomad /etc/nomad.d /opt/alloc_mounts
chmod -R 755 /opt/nomad /etc/nomad.d /opt/alloc_mounts

# Add nomad user to docker group (for compatibility)
usermod -aG docker nomad || true

# Get instance metadata
INTERNAL_IP=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
PROJECT_ID=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)

echo "Internal IP: $INTERNAL_IP"
echo "Project ID: $PROJECT_ID"
echo "Zone: $ZONE"

# Create Nomad client configuration with server_join
cat > /etc/nomad.d/client.hcl <<EON
data_dir  = "/opt/nomad"
log_level = "INFO"
log_file  = "/var/log/nomad.log"

bind_addr = "$INTERNAL_IP"

server {
  enabled = false
}

client {
  enabled = true
  network_interface = "ens4"
  
  node_class = "NODE_CLASS_PLACEHOLDER"
  
  # CNI configuration for bridge networking
  cni_path = "/opt/cni/bin"
  cni_config_dir = "/opt/cni/config"
  
  server_join {
    retry_join = [
      "provider=gce project_name=$PROJECT_ID tag_value=nomad-server"
    ]
    retry_max = 10
    retry_interval = "15s"
  }
}

plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
EON

# Create systemd service
cat > /etc/systemd/system/nomad.service <<EOS
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/nomad.d/client.hcl

[Service]
Type=notify
# Run as root - required for Docker driver in Nomad 1.8+
User=root
Group=root
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/client.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOS

# Set permissions - allow root to read config
chown root:root /etc/nomad.d/client.hcl
chmod 644 /etc/nomad.d/client.hcl

# Enable and start Nomad
systemctl daemon-reload
systemctl enable nomad
systemctl start nomad

echo "Nomad client setup complete!"

# Wait for Nomad to be ready
for i in {1..10}; do
  if nomad node status > /dev/null 2>&1; then
    echo "Nomad client is ready!"
    break
  fi
  echo "Waiting for Nomad client to be ready... (attempt $i)"
  sleep 10
done

date
echo "Startup script completed successfully!" 
#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting Nomad client setup..."

# Update system
apt-get update
apt-get install -y curl unzip jq

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Add nomad user to docker group
usermod -aG docker nomad || true

# Install Nomad
NOMAD_VERSION="1.8.0"
cd /tmp
curl -sSL https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
unzip nomad.zip
mv nomad /usr/local/bin/
chmod +x /usr/local/bin/nomad

# Create nomad user and directories
useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
mkdir -p /opt/nomad /etc/nomad.d
chown -R nomad:nomad /opt/nomad /etc/nomad.d

# Get management servers' private IPs (they should be running by now)
# For simplicity, we'll use the subnet CIDR to discover them
MANAGEMENT_SUBNET="10.0.1.0/24"

# Wait for management servers to be available
echo "Waiting for Nomad servers to be available..."
SERVERS=""
for i in {1..20}; do
  # Try to discover management servers via API (this is a simple approach)
  # In production, you'd use service discovery or DNS
  for ip in $(seq 2 10); do
    SERVER_IP="10.0.1.$$ip"
    if nc -z $$SERVER_IP 4647 2>/dev/null; then
      SERVERS="$$SERVERS\"$$SERVER_IP:4647\","
    fi
  done
  
  if [ ! -z "$$SERVERS" ]; then
    break
  fi
  
  echo "Attempt $$i: No servers found yet, waiting 30s..."
  sleep 30
done

# Remove trailing comma
SERVERS=$${SERVERS%,}

if [ -z "$$SERVERS" ]; then
  echo "ERROR: Could not find any Nomad servers!"
  exit 1
fi

echo "Found Nomad servers: $$SERVERS"

# Create Nomad client configuration
cat > /etc/nomad.d/client.hcl <<EOF
data_dir  = "/opt/nomad"
log_level = "INFO"
log_file  = "/var/log/nomad.log"

bind_addr = "0.0.0.0"

server {
  enabled = false
}

client {
  enabled = true
  network_interface = "ens4"
  
  servers = [$$SERVERS]
  
  %{ if node_class != "" }node_class = "${node_class}"%{ endif }
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}
EOF

# Create systemd service
cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/nomad.d/client.hcl

[Service]
Type=notify
User=nomad
Group=nomad
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/client.hcl
ExecReload=/bin/kill -HUP $$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chown nomad:nomad /etc/nomad.d/client.hcl
chmod 640 /etc/nomad.d/client.hcl

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

echo "Startup script completed successfully!" 
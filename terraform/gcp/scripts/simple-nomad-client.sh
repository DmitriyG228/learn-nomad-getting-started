#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/startup-script.log) 2>&1

echo "Starting simple Nomad client setup..."
date

# Update system and install dependencies
apt-get update
apt-get install -y curl unzip jq netcat-traditional docker.io

# Start Docker
systemctl enable docker
systemctl start docker

# Install Nomad
cd /tmp
curl -fsSL https://releases.hashicorp.com/nomad/1.8.0/nomad_1.8.0_linux_amd64.zip -o nomad.zip
unzip nomad.zip
mv nomad /usr/local/bin/
chmod +x /usr/local/bin/nomad

# Create nomad user and directories
useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
mkdir -p /opt/nomad /etc/nomad.d
chown -R nomad:nomad /opt/nomad /etc/nomad.d

# Add nomad user to docker group
usermod -aG docker nomad || true

# Wait for management servers to be available and discover them
echo "Waiting for Nomad servers to be available..."
SERVERS=""
for i in {1..20}; do
  # Try to discover management servers on the management subnet
  for ip in $(seq 2 10); do
    SERVER_IP="10.0.1.$ip"
    if nc -z $SERVER_IP 4647 2>/dev/null; then
      SERVERS="$SERVERS\"$SERVER_IP:4647\","
    fi
  done
  
  if [ ! -z "$SERVERS" ]; then
    break
  fi
  
  echo "Attempt $i: No servers found yet, waiting 30s..."
  sleep 30
done

# Remove trailing comma
SERVERS=${SERVERS%,}

if [ -z "$SERVERS" ]; then
  echo "ERROR: Could not find any Nomad servers!"
  exit 1
fi

echo "Found Nomad servers: $SERVERS"

# Create Nomad client configuration
cat > /etc/nomad.d/client.hcl <<EON
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
  
  servers = [$SERVERS]
  
  node_class = "NODE_CLASS_PLACEHOLDER"
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
User=nomad
Group=nomad
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/client.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOS

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

date
echo "Startup script completed successfully!"

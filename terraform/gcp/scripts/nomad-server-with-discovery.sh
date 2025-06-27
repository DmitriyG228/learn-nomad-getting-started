#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/startup-script.log) 2>&1

echo "Starting Nomad/Consul server setup with GCE discovery..."
date

# Update system and install dependencies
apt-get update
apt-get install -y curl unzip jq netcat-traditional docker.io

# Start Docker
systemctl enable docker
systemctl start docker

# Install Consul
cd /tmp
curl -fsSL https://releases.hashicorp.com/consul/1.17.0/consul_1.17.0_linux_amd64.zip -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
chmod +x /usr/local/bin/consul

# Install Nomad
curl -fsSL https://releases.hashicorp.com/nomad/1.8.0/nomad_1.8.0_linux_amd64.zip -o nomad.zip
unzip nomad.zip
mv nomad /usr/local/bin/
chmod +x /usr/local/bin/nomad

# Create users and directories
useradd --system --home /etc/consul.d --shell /bin/false consul || true
useradd --system --home /etc/nomad.d --shell /bin/false nomad || true
mkdir -p /opt/consul /etc/consul.d /opt/nomad /etc/nomad.d
chown -R consul:consul /opt/consul /etc/consul.d
chown -R nomad:nomad /opt/nomad /etc/nomad.d

# Get instance metadata
INTERNAL_IP=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
PROJECT_ID=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)

echo "Internal IP: $INTERNAL_IP"
echo "Project ID: $PROJECT_ID"
echo "Zone: $ZONE"

# Generate Consul configuration with GCE discovery
cat > /etc/consul.d/consul.hcl <<EOC
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"
server = true
bind_addr = "$INTERNAL_IP"
client_addr = "0.0.0.0"
bootstrap_expect = 3

retry_join = [
  "provider=gce project_name=$PROJECT_ID tag_value=nomad-server zone_pattern=us-central1-.*"
]

ui_config {
  enabled = true
}
connect {
  enabled = true
}
ports {
  grpc = 8502
}
EOC

# Generate Nomad configuration with GCE discovery
cat > /etc/nomad.d/server.hcl <<EON
datacenter = "dc1"
data_dir = "/opt/nomad"
log_level = "INFO"
bind_addr = "$INTERNAL_IP"

server {
  enabled = true
  bootstrap_expect = 3
  
  server_join {
    retry_join = [
      "provider=gce project_name=$PROJECT_ID tag_value=nomad-server zone_pattern=us-central1-.*"
    ]
    retry_max = 10
    retry_interval = "15s"
  }
}

client {
  enabled = false
  node_class = "management"
}

consul {
  address = "127.0.0.1:8500"
}

ui {
  enabled = true
}
EON

# Create Consul systemd service
cat > /etc/systemd/system/consul.service <<EOCS
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
Type=notify
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOCS

# Create Nomad systemd service
cat > /etc/systemd/system/nomad.service <<EONS
[Unit]
Description=Nomad
Documentation=https://www.nomadproject.io/
Requires=network-online.target consul.service
After=network-online.target consul.service
ConditionFileNotEmpty=/etc/nomad.d/server.hcl

[Service]
Type=notify
User=nomad
Group=nomad
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/server.hcl
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EONS

# Set permissions
chown consul:consul /etc/consul.d/consul.hcl
chown nomad:nomad /etc/nomad.d/server.hcl
chmod 640 /etc/consul.d/consul.hcl /etc/nomad.d/server.hcl

# Enable and start services
systemctl daemon-reload
systemctl enable consul
systemctl start consul

# Wait for Consul
echo "Waiting for Consul to be ready..."
for i in {1..30}; do
  if consul members > /dev/null 2>&1; then
    echo "Consul is ready!"
    break
  fi
  echo "Waiting for Consul... (attempt $i)"
  sleep 10
done

# Start Nomad
systemctl enable nomad
systemctl start nomad

# Wait for Nomad
echo "Waiting for Nomad to be ready..."
for i in {1..30}; do
  if nomad server members > /dev/null 2>&1; then
    echo "Nomad is ready!"
    break
  fi
  echo "Waiting for Nomad... (attempt $i)"
  sleep 10
done

echo "Management server setup complete!"
echo "Consul status:"
systemctl status consul --no-pager || true
echo "Nomad status:"
systemctl status nomad --no-pager || true

date
echo "Startup script completed successfully!" 
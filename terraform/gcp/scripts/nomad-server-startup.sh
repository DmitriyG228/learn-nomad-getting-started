#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting Nomad/Consul server setup..."

# Update system
apt-get update
apt-get install -y curl unzip jq netcat-traditional

# Install Docker (needed for some Nomad jobs)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Install Consul
CONSUL_VERSION="1.17.0"
cd /tmp
curl -sSL https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
chmod +x /usr/local/bin/consul

# Install Nomad
NOMAD_VERSION="1.8.0"
curl -sSL https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
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
INSTANCE_NAME=$$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
INTERNAL_IP=$$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
ZONE=$$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)

# Generate Consul configuration
cat > /etc/consul.d/consul.hcl <<EOF
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"
server = true

bind_addr = "$$INTERNAL_IP"
client_addr = "0.0.0.0"

bootstrap_expect = 3

retry_join = ["10.0.1.2", "10.0.1.3", "10.0.1.4", "10.0.1.5", "10.0.1.6"]

ui_config {
  enabled = true
}

connect {
  enabled = true
}

ports {
  grpc = 8502
}
EOF

# Generate Nomad configuration
cat > /etc/nomad.d/server.hcl <<EOF
datacenter = "dc1"
data_dir = "/opt/nomad"
log_level = "INFO"

bind_addr = "$$INTERNAL_IP"

server {
  enabled = true
  bootstrap_expect = 3
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
EOF

# Create Consul systemd service
cat > /etc/systemd/system/consul.service <<EOF
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
ExecReload=/bin/kill -HUP \$$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Create Nomad systemd service
cat > /etc/systemd/system/nomad.service <<EOF
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
ExecReload=/bin/kill -HUP \$$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
chown consul:consul /etc/consul.d/consul.hcl
chown nomad:nomad /etc/nomad.d/server.hcl
chmod 640 /etc/consul.d/consul.hcl /etc/nomad.d/server.hcl

# Enable and start services
systemctl daemon-reload

# Start Consul first
systemctl enable consul
systemctl start consul

# Wait for Consul to be ready
echo "Waiting for Consul to be ready..."
for i in {1..30}; do
  if consul members > /dev/null 2>&1; then
    echo "Consul is ready!"
    break
  fi
  echo "Waiting for Consul... (attempt $$i)"
  sleep 10
done

# Start Nomad
systemctl enable nomad
systemctl start nomad

# Wait for Nomad to be ready
echo "Waiting for Nomad to be ready..."
for i in {1..30}; do
  if nomad server members > /dev/null 2>&1; then
    echo "Nomad is ready!"
    break
  fi
  echo "Waiting for Nomad... (attempt $$i)"
  sleep 10
done

echo "Management server setup complete!"
echo "Instance: $$INSTANCE_NAME"
echo "Internal IP: $$INTERNAL_IP"
echo "Zone: $$ZONE"

# Log final status
systemctl status consul --no-pager || true
systemctl status nomad --no-pager || true

echo "Startup script completed successfully!" 
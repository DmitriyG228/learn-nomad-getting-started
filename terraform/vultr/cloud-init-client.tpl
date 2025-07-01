#cloud-config
# Cloud-init configuration for Nomad client nodes
# This script installs and configures Consul, Nomad, Docker, and required dependencies

package_update: true
package_upgrade: true

packages:
  - unzip
  - curl
  - jq
  - wget
  - htop
  - net-tools
  - ufw

# Disable UFW initially for easier setup
runcmd:
  # Disable UFW firewall (will be configured via Vultr firewall groups)
  - sudo ufw --force disable
  
  # Install Docker
  - curl -fsSL https://get.docker.com -o get-docker.sh
  - sh get-docker.sh
  - usermod -aG docker root
  - systemctl enable docker
  - systemctl start docker
  
%{ if gpu_enabled ~}
  # Install NVIDIA drivers and container toolkit for GPU support
  # Following NVIDIA's official installation guide
  - apt-get update
  - apt-get install -y ubuntu-drivers-common
  - ubuntu-drivers autoinstall
  
  # Install NVIDIA Container Toolkit
  - curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  - curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  - apt-get update
  - apt-get install -y nvidia-container-toolkit
  
  # Configure Docker to use NVIDIA runtime
  - nvidia-ctk runtime configure --runtime=docker
  - systemctl restart docker
%{ endif ~}
  
  # Install Consul (industry standard service discovery for Nomad)
  - CONSUL_VERSION="1.18.0"
  - cd /tmp
  - curl -sSL https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip -o consul.zip
  - unzip consul.zip
  - chmod +x consul
  - mv consul /usr/local/bin/consul
  - rm consul.zip
  
  # Create Consul user and directories
  - useradd --system --home /etc/consul.d --shell /bin/false consul
  - mkdir -p /opt/consul
  - mkdir -p /etc/consul.d
  - chown -R consul:consul /opt/consul
  - chown -R consul:consul /etc/consul.d
  
  # Get private IP for advertise addresses (VPC interface)
  - PRIVATE_IP=$(ip addr show enp8s0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
  
  # Create Consul configuration (client mode)
  - |
    cat << EOF > /etc/consul.d/consul.hcl
    # Consul Client Configuration
    data_dir = "/opt/consul"
    bind_addr = "0.0.0.0"
    
    datacenter = "${datacenter}"
    
    # Client configuration (not a server)
    server = false
    
    # Fallback retry_join using predictable VPC IPs for servers
    # Retry join list provided by Terraform (no hardcoded IPs)
    retry_join = [${retry_join}]
    retry_max = 3
    retry_interval = "15s"
    
    # Advertise addresses - use actual private IP
    advertise_addr = "$${PRIVATE_IP}"
    
    # Ports configuration
    ports {
      http = 8500
      https = 8501
      grpc = 8502
      grpc_tls = 8503
      dns = 8600
    }
    
    # ACL configuration (disabled for MVP)
    acl {
      enabled = false
    }
    
    # TLS configuration (disabled for MVP)
    tls {
      defaults {
        verify_incoming = false
        verify_outgoing = false
      }
    }
    
    # Logging
    log_level = "INFO"
    
    # Performance tuning
    performance {
      raft_multiplier = 1
    }
    EOF
  
  # Create Consul systemd service
  - |
    cat << 'EOF' > /etc/systemd/system/consul.service
    [Unit]
    Description=Consul
    Documentation=https://www.consul.io/docs/
    Wants=network-online.target
    After=network-online.target
    ConditionFileNotEmpty=/etc/consul.d/consul.hcl
    
    [Service]
    Type=notify
    User=consul
    Group=consul
    ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
    ExecReload=/bin/kill -HUP $MAINPID
    KillMode=process
    Restart=on-failure
    LimitNOFILE=65536
    
    [Install]
    WantedBy=multi-user.target
    EOF
  
  # Set proper permissions for Consul
  - chmod 640 /etc/consul.d/consul.hcl
  - chown consul:consul /etc/consul.d/consul.hcl
  
  # Install Nomad
  - NOMAD_VERSION="${nomad_version}"
  - cd /tmp
  - curl -sSL https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
  - unzip nomad.zip
  - chmod +x nomad
  - mv nomad /usr/local/bin/nomad
  - rm nomad.zip
  
  # Install CNI plugins for Nomad networking
  - CNI_VERSION="1.3.0"
  - mkdir -p /opt/cni/bin
  - cd /tmp
  - curl -sSL https://github.com/containernetworking/plugins/releases/download/v$${CNI_VERSION}/cni-plugins-linux-amd64-v$${CNI_VERSION}.tgz -o cni-plugins.tgz
  - tar -C /opt/cni/bin -xzf cni-plugins.tgz
  - chmod +x /opt/cni/bin/*
  - rm cni-plugins.tgz
  
  # Create CNI configuration directory
  - mkdir -p /etc/cni/net.d
  
  # Create Nomad user and directories
  - useradd --system --home /etc/nomad.d --shell /bin/false nomad
  - mkdir -p /opt/nomad
  - mkdir -p /opt/alloc_mounts
  - mkdir -p /etc/nomad.d
  - chown -R nomad:nomad /opt/nomad
  - chown -R nomad:nomad /opt/alloc_mounts
  - chown -R nomad:nomad /etc/nomad.d
  
  # Create Nomad configuration with Consul integration
  - |
    cat << EOF > /etc/nomad.d/nomad.hcl
    # Nomad Client Configuration
    data_dir = "/opt/nomad"
    bind_addr = "0.0.0.0"
    
    datacenter = "${datacenter}"
    region     = "${region}"
    
    # Server configuration (disabled on clients)
    server {
      enabled = false
    }
    
    # Client configuration
    client {
      enabled = true
      
      # Set node class for job placement
      node_class = "${node_class}"
      
      # Industry standard: Use Consul for service discovery
      # This follows HashiCorp's official patterns for robust cluster formation
      server_join {
        retry_join = ["provider=consul address=127.0.0.1:8500"]
        retry_max      = 3
        retry_interval = "15s"
      }
      
      # CNI plugins configuration
      cni_path = "/opt/cni/bin"
      cni_config_dir = "/etc/cni/net.d"
      
      %{ if gpu_enabled ~}
      # GPU-specific metadata for job placement
      meta {
        gpu_enabled = "true"
      }
      %{ endif ~}
    }
    
    # Advertise addresses - use actual private IP
    advertise {
      http = "$${PRIVATE_IP}:4646"
      rpc  = "$${PRIVATE_IP}:4647"
      serf = "$${PRIVATE_IP}:4648"
    }
    
    # Ports configuration
    ports {
      http = 4646
      rpc  = 4647
      serf = 4648
    }
    
    # ACL configuration (disabled for MVP)
    acl {
      enabled = false
    }
    
    # TLS configuration (disabled for MVP)
    tls {
      http = false
      rpc  = false
    }
    
    # Logging
    log_level = "INFO"
    log_file  = "/var/log/nomad/"
    
    # Plugin configuration
    plugin "docker" {
      config {
        allow_privileged = true
        volumes {
          enabled = true
        }
      }
    }
    
                    plugin "raw_exec" {
                  config {
                    enabled = false
                  }
                }
                
                %{ if gpu_enabled ~}
                # NVIDIA GPU device plugin configuration (built into Nomad 1.10+)
                plugin "nvidia" {
                  config {
                    enabled = true
                    fingerprint_period = "1m"
                  }
                }
                %{ endif ~}
                
                # Performance tuning
    limits {
      https_handshake_timeout   = "5s"
      http_max_conns_per_client = 100
      rpc_handshake_timeout     = "5s"
      rpc_max_conns_per_client  = 100
    }
    EOF
  
  # Create Nomad systemd service
  - |
    cat << 'EOF' > /etc/systemd/system/nomad.service
    [Unit]
    Description=Nomad
    Documentation=https://www.nomadproject.io/docs/
    Wants=network-online.target
    After=network-online.target
    ConditionFileNotEmpty=/etc/nomad.d/nomad.hcl
    
    [Service]
    Type=notify
    User=root
    Group=root
    ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/nomad.hcl
    ExecReload=/bin/kill -HUP $MAINPID
    KillMode=process
    Restart=on-failure
    LimitNOFILE=65536
    
    [Install]
    WantedBy=multi-user.target
    EOF
  
  # Create log directories
  - mkdir -p /var/log/nomad
  - mkdir -p /var/log/consul
  - chown nomad:nomad /var/log/nomad
  - chown consul:consul /var/log/consul
  
  # Set proper permissions for Nomad
  - chmod 640 /etc/nomad.d/nomad.hcl
  - chown nomad:nomad /etc/nomad.d/nomad.hcl
  
  # Enable and start Consul first (Nomad depends on it)
  - systemctl daemon-reload
  - systemctl enable consul
  - systemctl start consul
  
  # Wait for Consul to start and join cluster
  - sleep 30
  
  # Enable and start Nomad service
  - systemctl enable nomad
  - systemctl start nomad
  
  # Wait for Nomad to start
  - sleep 30
  
  # Configure firewall rules for VPC communication
  - ufw --force enable
  - ufw allow from ${vpc_cidr}
  - ufw allow 22/tcp
  - ufw reload
  
  # Set hostname
  - hostnamectl set-hostname ${hostname}
  
  # Log completion
  - echo "Consul and Nomad client setup completed at $(date)" >> /var/log/cloud-init-output.log

write_files:
  - path: /etc/profile.d/nomad.sh
    content: |
      export NOMAD_ADDR=http://127.0.0.1:4646
    permissions: '0644'
  
  - path: /etc/profile.d/consul.sh
    content: |
      export CONSUL_HTTP_ADDR=http://127.0.0.1:8500
    permissions: '0644'

# Set timezone
timezone: UTC

# Final reboot to ensure all services start properly
power_state:
  mode: reboot
  condition: True 
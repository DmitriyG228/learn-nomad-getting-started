#cloud-config
# Cloud-init configuration for Nomad client nodes
# This script installs and configures Nomad, Docker, and required dependencies

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
  
  %{ if gpu_enabled }
  # Install NVIDIA drivers and container toolkit for GPU nodes
  - apt-get update
  - apt-get install -y ubuntu-drivers-common
  - ubuntu-drivers autoinstall
  
  # Install NVIDIA Container Toolkit
  - distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
  - curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  - curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  - apt-get update
  - apt-get install -y nvidia-container-toolkit
  - nvidia-ctk runtime configure --runtime=docker
  - systemctl restart docker
  %{ endif }
  
  # Install Nomad
  - NOMAD_VERSION="${nomad_version}"
  - cd /tmp
  - curl -sSL https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
  - unzip nomad.zip
  - chmod +x nomad
  - mv nomad /usr/local/bin/nomad
  - rm nomad.zip
  
  # Create Nomad user and directories
  - useradd --system --home /etc/nomad.d --shell /bin/false nomad
  - mkdir -p /opt/nomad
  - mkdir -p /etc/nomad.d
  - chown -R nomad:nomad /opt/nomad
  - chown -R nomad:nomad /etc/nomad.d
  
  # Create Nomad configuration
  - |
    cat << 'EOF' > /etc/nomad.d/nomad.hcl
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
      
      server_join {
        retry_join = [${retry_join_servers}]
        retry_max      = 3
        retry_interval = "15s"
      }
      
      # Node class for workload targeting
      node_class = "${node_class}"
      
      # Resource configuration
      reserved {
        cpu    = 100
        memory = 256
      }
      
      # Host volumes (if needed for persistent storage)
      host_volume "docker_sock" {
        path      = "/var/run/docker.sock"
        read_only = false
      }
    }
    
    # Plugin configuration
    plugin "docker" {
      config {
        enabled = true
        
        # Docker daemon configuration
        endpoint = "unix:///var/run/docker.sock"
        
        # Allow privileged containers (needed for some workloads)
        allow_privileged = true
        
        # Volume configuration
        volumes {
          enabled      = true
          selinuxlabel = "z"
        }
        
        %{ if gpu_enabled }
        # GPU support
        nvidia_runtime = "nvidia"
        %{ endif }
      }
    }
    
    %{ if gpu_enabled }
    # NVIDIA GPU plugin configuration
    plugin "nvidia" {
      config {
        enabled = true
      }
    }
    %{ endif }
    
    # Advertise addresses
    advertise {
      http = "{{ GetPrivateInterfaces | attr \"address\" }}:4646"
      rpc  = "{{ GetPrivateInterfaces | attr \"address\" }}:4647"
      serf = "{{ GetPrivateInterfaces | attr \"address\" }}:4648"
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
    User=nomad
    Group=nomad
    ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/nomad.hcl
    ExecReload=/bin/kill -HUP $MAINPID
    KillMode=process
    Restart=on-failure
    LimitNOFILE=65536
    
    [Install]
    WantedBy=multi-user.target
    EOF
  
  # Create log directory
  - mkdir -p /var/log/nomad
  - chown nomad:nomad /var/log/nomad
  
  # Set proper permissions
  - chmod 640 /etc/nomad.d/nomad.hcl
  - chown nomad:nomad /etc/nomad.d/nomad.hcl
  
  # Add nomad user to docker group for Docker plugin
  - usermod -aG docker nomad
  
  # Enable and start Nomad service
  - systemctl daemon-reload
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
  
  %{ if gpu_enabled }
  # Verify GPU setup (for GPU nodes)
  - nvidia-smi > /var/log/gpu-setup.log 2>&1 || echo "GPU setup verification failed" >> /var/log/gpu-setup.log
  %{ endif }
  
  # Log completion
  - echo "Nomad client setup completed at $(date)" >> /var/log/cloud-init-output.log

write_files:
  - path: /etc/profile.d/nomad.sh
    content: |
      export NOMAD_ADDR=http://127.0.0.1:4646
    permissions: '0644'

# Set timezone
timezone: UTC

# Final reboot to ensure all services start properly
power_state:
  mode: reboot
  condition: True 
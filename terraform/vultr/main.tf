# Generate SSH key pair for instances
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Upload SSH public key to Vultr
resource "vultr_ssh_key" "main" {
  name    = var.ssh_key_name
  ssh_key = tls_private_key.ssh_key.public_key_openssh
}

# Create VPC network
resource "vultr_vpc" "main" {
  description    = "${var.project_name}-${var.environment}-vpc"
  region         = var.region
  v4_subnet      = "10.0.0.0"
  v4_subnet_mask = 16
}

# Create firewall group for Nomad cluster
resource "vultr_firewall_group" "nomad_cluster" {
  description = "${var.project_name}-${var.environment}-nomad-cluster"
}

# Firewall rules for Nomad cluster
resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "SSH access"
}

resource "vultr_firewall_rule" "nomad_http" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "4646"
  notes             = "Nomad HTTP API"
}

resource "vultr_firewall_rule" "nomad_rpc" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "4647"
  notes             = "Nomad RPC (internal)"
}

resource "vultr_firewall_rule" "nomad_serf" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "4648"
  notes             = "Nomad Serf (internal)"
}

resource "vultr_firewall_rule" "docker_ports" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "8000:9000"
  notes             = "Application ports range"
}

resource "vultr_firewall_rule" "vpc_internal" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "1:65535"
  notes             = "All internal VPC traffic"
}

# Generate random suffix for hostnames
resource "random_id" "cluster" {
  byte_length = 4
}

# Data sources for template rendering
locals {
  cluster_id = random_id.cluster.hex
  
  # Generate server join list (all servers join each other)
  server_join_list = [
    for i in range(var.nomad_server_count) :
    "\"{{ GetPrivateInterfaces | include \"network\" \"10.0.0.0/16\" | attr \"address\" }}\""
  ]
  
  retry_join_servers = join(", ", local.server_join_list)
}

# Nomad Server Instances
resource "vultr_instance" "nomad_servers" {
  count               = var.nomad_server_count
  plan                = var.nomad_server_plan
  region              = var.region
  os_id               = var.os_id
  hostname            = "${var.project_name}-server-${count.index + 1}-${local.cluster_id}"
  ssh_key_ids         = [vultr_ssh_key.main.id]
  firewall_group_id   = vultr_firewall_group.nomad_cluster.id
  vpc_ids             = [vultr_vpc.main.id]
  enable_ipv6         = false
  backups             = "disabled"
  ddos_protection     = false

  user_data = templatefile("${path.module}/cloud-init-server.tpl", {
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    server_count         = var.nomad_server_count
    retry_join_servers   = local.retry_join_servers
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-server-${count.index + 1}-${local.cluster_id}"
  })

  # Wait for VPC to be ready
  depends_on = [vultr_vpc.main]
}

# Nomad Client Instances - Static Services
resource "vultr_instance" "nomad_clients_static" {
  count               = var.nomad_client_static_count
  plan                = var.nomad_client_static_plan
  region              = var.region
  os_id               = var.os_id
  hostname            = "${var.project_name}-client-static-${count.index + 1}-${local.cluster_id}"
  ssh_key_ids         = [vultr_ssh_key.main.id]
  firewall_group_id   = vultr_firewall_group.nomad_cluster.id
  vpc_ids             = [vultr_vpc.main.id]
  enable_ipv6         = false
  backups             = "disabled"
  ddos_protection     = false

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    retry_join_servers   = local.retry_join_servers
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-static-${count.index + 1}-${local.cluster_id}"
    node_class          = "static"
    gpu_enabled         = false
  })

  # Wait for servers to be created first
  depends_on = [vultr_instance.nomad_servers]
}

# Nomad Client Instances - Workload
resource "vultr_instance" "nomad_clients_workload" {
  count               = var.nomad_client_workload_count
  plan                = var.nomad_client_workload_plan
  region              = var.region
  os_id               = var.os_id
  hostname            = "${var.project_name}-client-workload-${count.index + 1}-${local.cluster_id}"
  ssh_key_ids         = [vultr_ssh_key.main.id]
  firewall_group_id   = vultr_firewall_group.nomad_cluster.id
  vpc_ids             = [vultr_vpc.main.id]
  enable_ipv6         = false
  backups             = "disabled"
  ddos_protection     = false

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    retry_join_servers   = local.retry_join_servers
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-workload-${count.index + 1}-${local.cluster_id}"
    node_class          = "workload"
    gpu_enabled         = false
  })

  # Wait for servers to be created first
  depends_on = [vultr_instance.nomad_servers]
}

# Nomad Client Instances - GPU
resource "vultr_instance" "nomad_clients_gpu" {
  count               = var.nomad_client_gpu_count
  plan                = var.nomad_client_gpu_plan
  region              = var.region
  os_id               = var.os_id
  hostname            = "${var.project_name}-client-gpu-${count.index + 1}-${local.cluster_id}"
  ssh_key_ids         = [vultr_ssh_key.main.id]
  firewall_group_id   = vultr_firewall_group.nomad_cluster.id
  vpc_ids             = [vultr_vpc.main.id]
  enable_ipv6         = false
  backups             = "disabled"
  ddos_protection     = false

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    retry_join_servers   = local.retry_join_servers
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-gpu-${count.index + 1}-${local.cluster_id}"
    node_class          = "gpu"
    gpu_enabled         = true
  })

  # Wait for servers to be created first
  depends_on = [vultr_instance.nomad_servers]
}

# Load Balancer for Nomad Servers
resource "vultr_load_balancer" "nomad_servers" {
  region              = var.region
  label               = "${var.project_name}-${var.environment}-nomad-lb"
  balancing_algorithm = "roundrobin"
  proxy_protocol      = false
  health_check {
    protocol            = "tcp"
    port                = 4646
    path                = ""
    check_interval      = 15
    response_timeout    = 5
    unhealthy_threshold = 3
    healthy_threshold   = 2
  }

  forwarding_rules {
    frontend_protocol = "tcp"
    frontend_port     = 4646
    backend_protocol  = "tcp"
    backend_port      = 4646
  }

  # Attach all server instances to the load balancer
  attached_instances = vultr_instance.nomad_servers[*].id

  # Attach to VPC
  vpc = vultr_vpc.main.id

  depends_on = [vultr_instance.nomad_servers]
}

# Save SSH private key locally for access
resource "local_file" "ssh_private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/ssh-key-${var.project_name}-${var.environment}.pem"
  file_permission = "0600"
} 
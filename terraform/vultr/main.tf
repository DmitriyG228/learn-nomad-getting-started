# Use local SSH public key for instances
data "local_file" "ssh_public_key" {
  filename = pathexpand("~/.ssh/id_rsa.pub")
}

# Upload SSH public key to Vultr
resource "vultr_ssh_key" "main" {
  name    = var.ssh_key_name
  ssh_key = data.local_file.ssh_public_key.content
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

# Consul firewall rules for service discovery
resource "vultr_firewall_rule" "consul_http" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "8500"
  notes             = "Consul HTTP API (internal)"
}

resource "vultr_firewall_rule" "consul_grpc" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "8502"
  notes             = "Consul gRPC (internal)"
}

resource "vultr_firewall_rule" "consul_dns" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "8600"
  notes             = "Consul DNS (internal)"
}

resource "vultr_firewall_rule" "consul_dns_udp" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "10.0.0.0"
  subnet_size       = 16
  port              = "8600"
  notes             = "Consul DNS UDP (internal)"
}

# Redis firewall rule for cross-VM connectivity
resource "vultr_firewall_rule" "redis" {
  firewall_group_id = vultr_firewall_group.nomad_cluster.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "6379"
  notes             = "Redis database (cross-VM access)"
}

# Generate random suffix for hostnames
resource "random_id" "cluster" {
  byte_length = 4
}

# Data sources for template rendering
locals {
  cluster_id = random_id.cluster.hex
  
  # Predictable server IPs based on VPC subnet (10.0.0.0/16)
  # Vultr assigns IPs sequentially starting from 10.0.0.4
  server_ips = [
    "10.0.0.4",
    "10.0.0.5", 
    "10.0.0.6"
  ]
  
  # Server retry_join lists (each server excludes itself)
  server_retry_joins = [
    join(", ", formatlist("\"%s\"", [for i, ip in local.server_ips : ip if i != 0])), # Server 1: joins 10.0.0.5, 10.0.0.6
    join(", ", formatlist("\"%s\"", [for i, ip in local.server_ips : ip if i != 1])), # Server 2: joins 10.0.0.4, 10.0.0.6
    join(", ", formatlist("\"%s\"", [for i, ip in local.server_ips : ip if i != 2]))  # Server 3: joins 10.0.0.4, 10.0.0.5
  ]
  
  # Client retry_join (all server IPs)
  client_retry_join = join(", ", formatlist("\"%s\"", local.server_ips))
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
  
  # Industry standard: Tag instances for auto-join
  # Vultr expects a set of strings for tags
  tags = [
    "Name:${var.project_name}-server-${count.index + 1}-${local.cluster_id}",
    "NomadAutoJoin:auto-join",
    "NomadType:server",
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ConsulAutoJoin:auto-join"
  ]

  user_data = templatefile("${path.module}/cloud-init-server.tpl", {
    retry_join = local.server_retry_joins[count.index]
    hostname   = "${var.project_name}-server-${count.index + 1}-${local.cluster_id}"
    CONSUL_VERSION = "1.18.0"
            NOMAD_VERSION = "1.10.2"
    node_class = "management"
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
  
  # Industry standard: Tag instances for auto-join
  tags = [
    "Name:${var.project_name}-client-static-${count.index + 1}-${local.cluster_id}",
    "NomadAutoJoin:auto-join",
    "NomadType:client-static",
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ConsulAutoJoin:auto-join"
  ]

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    retry_join = local.client_retry_join
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-static-${count.index + 1}-${local.cluster_id}"
    node_class          = "core"
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
  
  # Industry standard: Tag instances for auto-join
  tags = [
    "Name:${var.project_name}-client-workload-${count.index + 1}-${local.cluster_id}",
    "NomadAutoJoin:auto-join",
    "NomadType:client-workload",
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ConsulAutoJoin:auto-join"
  ]

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    retry_join = local.client_retry_join
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-workload-${count.index + 1}-${local.cluster_id}"
    node_class          = "core"
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
  
  # Industry standard: Tag instances for auto-join
  tags = [
    "Name:${var.project_name}-client-gpu-${count.index + 1}-${local.cluster_id}",
    "NomadAutoJoin:auto-join",
    "NomadType:client-gpu",
    "Environment:${var.environment}",
    "Project:${var.project_name}",
    "ConsulAutoJoin:auto-join"
  ]

  user_data = templatefile("${path.module}/cloud-init-client.tpl", {
    retry_join = local.client_retry_join
    nomad_version         = var.nomad_version
    datacenter           = var.nomad_datacenter
    region               = var.nomad_region
    vpc_cidr            = "10.0.0.0/16"
    hostname            = "${var.project_name}-client-gpu-${count.index + 1}-${local.cluster_id}"
    node_class          = "gpu"
    gpu_enabled         = true
  })

  # Wait for servers to be created first
  depends_on = [vultr_instance.nomad_servers]
}

# Load balancer for Nomad UI
resource "vultr_load_balancer" "nomad_servers" {
  region = var.region
  label  = "${var.project_name}-${var.environment}-nomad-lb"
  vpc    = vultr_vpc.main.id

  balancing_algorithm = "roundrobin"
  ssl_redirect        = false
  proxy_protocol      = false

  health_check {
    protocol            = "tcp"
    port                = 4646
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

  attached_instances = vultr_instance.nomad_servers[*].id
}

# Outputs
output "nomad_ui_url" {
  description = "URL for Nomad UI"
  value       = "http://${vultr_load_balancer.nomad_servers.ipv4}:4646"
}

output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = vultr_load_balancer.nomad_servers.ipv4
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = "${vultr_vpc.main.v4_subnet}/${vultr_vpc.main.v4_subnet_mask}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = vultr_vpc.main.id
}

output "firewall_group_id" {
  description = "Firewall group ID"
  value       = vultr_firewall_group.nomad_cluster.id
}

output "nomad_servers" {
  description = "Nomad server instances"
  value = {
    count        = length(vultr_instance.nomad_servers)
    hostnames    = vultr_instance.nomad_servers[*].hostname
    instance_ids = vultr_instance.nomad_servers[*].id
    private_ips  = vultr_instance.nomad_servers[*].internal_ip
    public_ips   = vultr_instance.nomad_servers[*].main_ip
  }
}

output "nomad_clients_static" {
  description = "Nomad static client instances"
  value = {
    count        = length(vultr_instance.nomad_clients_static)
    hostnames    = vultr_instance.nomad_clients_static[*].hostname
    instance_ids = vultr_instance.nomad_clients_static[*].id
    private_ips  = vultr_instance.nomad_clients_static[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_static[*].main_ip
  }
}

output "nomad_clients_workload" {
  description = "Nomad workload client instances"
  value = {
    count        = length(vultr_instance.nomad_clients_workload)
    hostnames    = vultr_instance.nomad_clients_workload[*].hostname
    instance_ids = vultr_instance.nomad_clients_workload[*].id
    private_ips  = vultr_instance.nomad_clients_workload[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_workload[*].main_ip
  }
}

output "nomad_clients_gpu" {
  description = "Nomad GPU client instances"
  value = {
    count        = length(vultr_instance.nomad_clients_gpu)
    hostnames    = vultr_instance.nomad_clients_gpu[*].hostname
    instance_ids = vultr_instance.nomad_clients_gpu[*].id
    private_ips  = vultr_instance.nomad_clients_gpu[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_gpu[*].main_ip
  }
}

output "ssh_command_servers" {
  description = "SSH commands for server instances"
  value = [
    for i, server in vultr_instance.nomad_servers : "ssh root@${server.main_ip}  # ${server.hostname}"
  ]
}

output "ssh_command_clients" {
  description = "SSH commands for client instances"
  value = concat(
    [for i, client in vultr_instance.nomad_clients_static : "ssh root@${client.main_ip}  # ${client.hostname} (static services)"],
    [for i, client in vultr_instance.nomad_clients_workload : "ssh root@${client.main_ip}  # ${client.hostname} (workload)"],
    [for i, client in vultr_instance.nomad_clients_gpu : "ssh root@${client.main_ip}  # ${client.hostname} (GPU)"]
  )
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    region                 = var.region
    vpc_cidr              = "${vultr_vpc.main.v4_subnet}/${vultr_vpc.main.v4_subnet_mask}"
    nomad_servers          = var.nomad_server_count
    static_clients         = var.nomad_client_static_count
    workload_clients       = var.nomad_client_workload_count
    gpu_clients            = var.nomad_client_gpu_count
    total_instances        = var.nomad_server_count + var.nomad_client_static_count + var.nomad_client_workload_count + var.nomad_client_gpu_count
    nomad_ui               = "http://${vultr_load_balancer.nomad_servers.ipv4}:4646"
    estimated_monthly_cost = (var.nomad_server_count * 12) + (var.nomad_client_static_count * 12) + (var.nomad_client_workload_count * 24) + (var.nomad_client_gpu_count * 200)
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Access Nomad UI at: http://${vultr_load_balancer.nomad_servers.ipv4}:4646",
    "2. Verify cluster health: nomad server members",
    "3. Check client status: nomad node status",
    "4. Deploy jobs from vexa-deployment/jobs/ directory",
    "5. Monitor logs: nomad logs -f <allocation-id>",
  ]
}

# --- Post provisioning: push Consul retry list and restart services ---
# REMOVED: null_resource approach was causing infinite loops
# Instead, we'll use templatefile to embed retry_join configuration directly 

# --- Nomad Job Deployment ---

# Wait for Nomad cluster to be ready before deploying jobs
resource "null_resource" "wait_for_nomad" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Nomad cluster to be ready..."
      for i in {1..30}; do
        if curl -s http://${vultr_load_balancer.nomad_servers.ipv4}:4646/v1/status/leader > /dev/null 2>&1; then
          echo "Nomad cluster is ready!"
          break
        fi
        echo "Attempt $i/30: Waiting for Nomad cluster..."
        sleep 10
      done
    EOT
  }

  depends_on = [vultr_load_balancer.nomad_servers]
}

# Create Nomad variables for database configuration
resource "nomad_variable" "database" {
  path = "secret/vexa/db"

  items = {
    host     = var.db_host
    port     = var.db_port
    name     = var.db_name
    user     = var.db_user
    password = var.db_password
  }

  depends_on = [null_resource.wait_for_nomad]
}

# Create Nomad variable for admin API token
resource "nomad_variable" "admin_api" {
  path = "secret/vexa/admin-api"

  items = {
    token = var.admin_api_token
  }

  depends_on = [null_resource.wait_for_nomad]
}

# Get a list of all .nomad.hcl files in the jobs directory
locals {
  job_files = fileset("${path.module}/../../jobs", "*.nomad.hcl")
}

# Deploy all Nomad jobs
resource "nomad_job" "vexa_services" {
  for_each = local.job_files

  jobspec = file("${path.module}/../../jobs/${each.value}")

  # Ensure jobs are deployed after variables are created
  depends_on = [nomad_variable.database, nomad_variable.admin_api]
}

# Output deployed jobs status
output "deployed_jobs" {
  description = "Status of deployed Nomad jobs"
  value = {
    for job_name, job in nomad_job.vexa_services : job_name => {
      id     = job.id
      name   = job.name
      status = job.status
    }
  }
}

output "nomad_variables_managed" {
  description = "Nomad variables managed by this Terraform configuration"
  value = [
    nomad_variable.database.path,
    nomad_variable.admin_api.path
  ]
} 
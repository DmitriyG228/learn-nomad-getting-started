output "load_balancer_ip" {
  description = "Public IP address of the Nomad servers load balancer"
  value       = vultr_load_balancer.nomad_servers.ipv4
}

output "nomad_ui_url" {
  description = "URL to access the Nomad web UI"
  value       = "http://${vultr_load_balancer.nomad_servers.ipv4}:4646"
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = vultr_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = "${vultr_vpc.main.v4_subnet}/${vultr_vpc.main.v4_subnet_mask}"
}

output "firewall_group_id" {
  description = "ID of the firewall group"
  value       = vultr_firewall_group.nomad_cluster.id
}

output "nomad_servers" {
  description = "Details of Nomad server instances"
  value = {
    count       = length(vultr_instance.nomad_servers)
    instance_ids = vultr_instance.nomad_servers[*].id
    private_ips  = vultr_instance.nomad_servers[*].internal_ip
    public_ips   = vultr_instance.nomad_servers[*].main_ip
    hostnames    = vultr_instance.nomad_servers[*].hostname
  }
}

output "nomad_clients_static" {
  description = "Details of static service client instances"
  value = {
    count       = length(vultr_instance.nomad_clients_static)
    instance_ids = vultr_instance.nomad_clients_static[*].id
    private_ips  = vultr_instance.nomad_clients_static[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_static[*].main_ip
    hostnames    = vultr_instance.nomad_clients_static[*].hostname
  }
}

output "nomad_clients_workload" {
  description = "Details of workload client instances"
  value = {
    count       = length(vultr_instance.nomad_clients_workload)
    instance_ids = vultr_instance.nomad_clients_workload[*].id
    private_ips  = vultr_instance.nomad_clients_workload[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_workload[*].main_ip
    hostnames    = vultr_instance.nomad_clients_workload[*].hostname
  }
}

output "nomad_clients_gpu" {
  description = "Details of GPU client instances"
  value = {
    count       = length(vultr_instance.nomad_clients_gpu)
    instance_ids = vultr_instance.nomad_clients_gpu[*].id
    private_ips  = vultr_instance.nomad_clients_gpu[*].internal_ip
    public_ips   = vultr_instance.nomad_clients_gpu[*].main_ip
    hostnames    = vultr_instance.nomad_clients_gpu[*].hostname
  }
}

output "ssh_command_servers" {
  description = "SSH commands to connect to Nomad servers"
  value = [
    for i, server in vultr_instance.nomad_servers :
    "ssh root@${server.main_ip}  # ${server.hostname}"
  ]
}

output "ssh_command_clients" {
  description = "SSH commands to connect to client nodes"
  value = concat(
    [
      for i, client in vultr_instance.nomad_clients_static :
      "ssh root@${client.main_ip}  # ${client.hostname} (static services)"
    ],
    [
      for i, client in vultr_instance.nomad_clients_workload :
      "ssh root@${client.main_ip}  # ${client.hostname} (workload)"
    ],
    [
      for i, client in vultr_instance.nomad_clients_gpu :
      "ssh root@${client.main_ip}  # ${client.hostname} (GPU)"
    ]
  )
}

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    region              = var.region
    vpc_cidr           = var.vpc_cidr
    nomad_servers      = var.nomad_server_count
    static_clients     = var.nomad_client_static_count
    workload_clients   = var.nomad_client_workload_count
    gpu_clients        = var.nomad_client_gpu_count
    total_instances    = var.nomad_server_count + var.nomad_client_static_count + var.nomad_client_workload_count + var.nomad_client_gpu_count
    nomad_ui          = "http://${vultr_load_balancer.nomad_servers.ipv4}:4646"
    estimated_monthly_cost = "${(var.nomad_server_count * 48) + (var.nomad_client_static_count * 48) + (var.nomad_client_workload_count * 24) + (var.nomad_client_gpu_count * 43) + 10}"
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Access Nomad UI at: http://${vultr_load_balancer.nomad_servers.ipv4}:4646",
    "2. Verify cluster health: nomad server members",
    "3. Check client status: nomad node status",
    "4. Deploy jobs from vexa-deployment/jobs/ directory",
    "5. Monitor logs: nomad logs -f <allocation-id>"
  ]
} 
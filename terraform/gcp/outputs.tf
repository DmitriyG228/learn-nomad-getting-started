# Outputs for Phase 3.0 - Static MIG Demo
# Following HashiCorp best practices from Nomad tutorials

# External data source to get first management server IP
data "external" "management_ip" {
  program = ["bash", "-c", "ip=$(gcloud compute instances list --filter='name~management-server' --format='value(networkInterfaces[0].accessConfigs[0].natIP)' | head -1); echo \"{\\\"ip\\\": \\\"$ip\\\"}\""]
}

output "phase_3_0_info" {
  description = "Phase 3.0 deployment information"
  value = <<-EOT
    
    🚀 Phase 3.0 Static MIG Demo - DEPLOYED
    =====================================
    
    📊 Infrastructure Status:
    • Management Servers: ${google_compute_instance_group_manager.management.target_size} nodes (Nomad/Consul servers)
    • Core Services: ${google_compute_instance_group_manager.core.target_size} nodes (API Gateway, Bot Manager, etc.)
    • Bot Servers: ${google_compute_instance_group_manager.bots.target_size} nodes (MIG for bot workloads)
    
    🌐 PRODUCTION ENDPOINTS:
    • API Gateway: http://${google_compute_address.api_gw.address}:8926
    
    🎯 Admin Access (Direct - Best Practice):
    • Nomad UI: http://${data.external.management_ip.result.ip}:4646
    • Consul UI: http://${data.external.management_ip.result.ip}:8500
    • Alternative IPs: gcloud compute instances list --filter="name~management" --format="value(networkInterfaces[0].accessConfigs[0].natIP)"
    
    📋 Next Steps:
    1. Check Nomad UI for cluster health
    2. Test API Gateway endpoint for service access
    3. Deploy additional bot workloads to test scaling
    
    💡 Commands to check infrastructure:
    • List all instances: gcloud compute instances list --filter="name~(management|core|bot)-server"
    • Get management IPs: gcloud compute instances list --filter="name~management" --format="value(networkInterfaces[0].accessConfigs[0].natIP)"
  EOT
}

output "management_access_urls" {
  description = "Direct access URLs for Nomad and Consul admin interfaces"
  value = {
    nomad_ui = "http://${data.external.management_ip.result.ip}:4646"
    consul_ui = "http://${data.external.management_ip.result.ip}:8500"
    get_all_ips_command = "gcloud compute instances list --filter='name~management-server' --format='value(networkInterfaces[0].accessConfigs[0].natIP)'"
  }
}

output "db_private_ip" {
  description = "Private IP address of Cloud SQL instance"
  value       = google_sql_database_instance.dev.private_ip_address
}

output "db_name" {
  description = "Database name"
  value       = google_sql_database.vexa.name
}

output "db_user" {
  description = "Database user"
  value       = google_sql_user.postgres.name
} 
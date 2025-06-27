# Outputs for Phase 3.0 - Static MIG Demo
# Following HashiCorp best practices from Nomad tutorials

output "phase_3_0_info" {
  description = "Phase 3.0 deployment information"
  value = <<-EOT
    
    🚀 Phase 3.0 Static MIG Demo - DEPLOYED
    =====================================
    
    Management Servers (${google_compute_instance_group_manager.management.target_size} nodes):
    $(gcloud compute instances list --filter="name~management-server" --format="table(name,status,networkInterfaces[0].networkIP:label=INTERNAL_IP,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)")
    
    Core Services (${google_compute_instance_group_manager.core.target_size} nodes):
    $(gcloud compute instances list --filter="name~core-server" --format="table(name,status,networkInterfaces[0].networkIP:label=INTERNAL_IP,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)")
    
    Bot Servers (${google_compute_instance_group_manager.bots.target_size} nodes - MIG):
    $(gcloud compute instances list --filter="name~bot-server" --format="table(name,status,networkInterfaces[0].networkIP:label=INTERNAL_IP,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)")
    
    🎯 Access Points:
    • Nomad UI: http://<management-server-external-ip>:4646
    • Consul UI: http://<management-server-external-ip>:8500
    
    📋 Next Steps:
    1. Wait ~5 minutes for startup scripts to complete
    2. Check Nomad UI for cluster health
    3. Deploy Nomad jobs to test workload placement
    
    💡 Use: gcloud compute instances list --filter="name~management" to get management IPs
  EOT
} 
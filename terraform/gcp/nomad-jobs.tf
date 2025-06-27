# Nomad Job Deployment Configuration

# Use a simpler approach - we'll set this via environment variable or use local exec
# For now, comment out the dynamic provider configuration
# The Nomad provider will need to be configured after infrastructure is deployed

# Nomad provider - will be configured via NOMAD_ADDR environment variable
# The data source is not needed here
# data "google_compute_instance_group" "management" { ... }

provider "nomad" {
  address = var.nomad_addr
}


# Variables for Nomad configuration are defined in variables.tf

# === Nomad Variables ===

# Database credentials (already created in terraform apply)
# This just ensures it exists and has the right values
resource "nomad_variable" "database" {
  path = "secret/vexa/db"
  
  items = {
    host     = google_sql_database_instance.dev.private_ip_address
    port     = "5432"
    name     = google_sql_database.vexa.name
    user     = google_sql_user.postgres.name
    password = random_password.db_pass.result
  }
  
  depends_on = [
    google_sql_database_instance.dev,
    google_sql_database.vexa,
    google_sql_user.postgres,
    random_password.db_pass
  ]
}

# Admin API token
resource "nomad_variable" "admin_api" {
  path = "secret/vexa/admin-api"
  
  items = {
    token = var.admin_api_token
  }
}

# === Job Deployment ===

# Get all job files, excluding ones that shouldn't auto-deploy
locals {
  all_job_files = fileset("../../jobs", "*.nomad.hcl")
  
  # Exclude jobs that need special handling or are environment-specific
  excluded_jobs = toset([
    "whisperlive-cpu.nomad.hcl",  # May not be needed in cloud
    "db-migrate.nomad.hcl"        # One-time migration job
  ])
  
  # Jobs to deploy automatically
  deployment_jobs = setsubtract(local.all_job_files, local.excluded_jobs)
}

# Deploy Redis first (other services depend on it)
resource "nomad_job" "redis" {
  count = contains(local.deployment_jobs, "redis.nomad.hcl") ? 1 : 0
  
  jobspec = file("../../jobs/redis.nomad.hcl")
  
  # Ensure infrastructure is ready
  depends_on = [
    google_compute_instance_group_manager.core,
    google_compute_instance_group_manager.bots,
    nomad_variable.database,
    nomad_variable.admin_api
  ]
}

# Deploy core services (admin-api, bot-manager, transcription-collector)
resource "nomad_job" "core_services" {
  for_each = toset([
    "admin-api.nomad.hcl",
    "bot-manager.nomad.hcl", 
    "transcription-collector.nomad.hcl"
  ])
  
  jobspec = contains(local.deployment_jobs, each.value) ? file("../../jobs/${each.value}") : ""
  
  depends_on = [
    nomad_job.redis,
    nomad_variable.database,
    nomad_variable.admin_api
  ]
}

# Deploy WhisperLive services
resource "nomad_job" "whisperlive_services" {
  for_each = toset([
    "whisperlive-gpu.nomad.hcl",
    # "whisperlive-cpu.nomad.hcl" - excluded for cloud deployment
  ])
  
  jobspec = contains(local.deployment_jobs, each.value) ? file("../../jobs/${each.value}") : ""
  
  depends_on = [
    nomad_job.redis,
    nomad_variable.database
  ]
}

# Deploy remaining services (API gateway, bot instances, monitoring)
resource "nomad_job" "other_services" {
  for_each = setsubtract(local.deployment_jobs, toset([
    "redis.nomad.hcl",
    "admin-api.nomad.hcl",
    "bot-manager.nomad.hcl",
    "transcription-collector.nomad.hcl", 
    "whisperlive-gpu.nomad.hcl"
  ]))
  
  jobspec = file("../../jobs/${each.value}")
  
  depends_on = [
    nomad_job.core_services,
    nomad_job.whisperlive_services
  ]
}

# === Outputs ===

output "nomad_deployment_status" {
  description = "Status of deployed Nomad jobs"
  value = {
    redis_deployed = length(nomad_job.redis) > 0 ? nomad_job.redis[0].name : "not deployed"
    
    core_services = {
      for job_name, job in nomad_job.core_services : job_name => {
        id     = job.id
        name   = job.name
        status = job.status
      }
    }
    
    whisperlive_services = {
      for job_name, job in nomad_job.whisperlive_services : job_name => {
        id     = job.id  
        name   = job.name
        status = job.status
      }
    }
    
    other_services = {
      for job_name, job in nomad_job.other_services : job_name => {
        id     = job.id
        name   = job.name 
        status = job.status
      }
    }
  }
}

output "nomad_variables_created" {
  description = "Nomad variables created by this deployment"
  value = [
    nomad_variable.database.path,
    nomad_variable.admin_api.path
  ]
}

output "nomad_ui_url" {
  description = "URL to access Nomad UI (use any management server IP)"
  value = "http://<MANAGEMENT_SERVER_IP>:4646/ui"
}

output "management_servers_command" {
  description = "Command to get management server IPs"
  value = "gcloud compute instances list --filter='name~management-server' --format='value(networkInterfaces[0].accessConfigs[0].natIP)'"
} 
# Nomad Job Deployment Configuration – Nomad workspace

############################
# Nomad Variables stored in Nomad variable store
############################

resource "nomad_variable" "database" {
  path = "secret/vexa/db"

  items = {
    host     = local.db_host
    port     = "5432"
    name     = local.db_name
    user     = local.db_user
    password = var.db_password
  }
}

resource "nomad_variable" "admin_api" {
  path = "secret/vexa/admin-api"

  items = {
    token = var.admin_api_token
  }
}

############################
# Job deployment
############################

locals {
  all_job_files = fileset("../../jobs", "*.nomad.hcl")

  excluded_jobs = toset([
    "whisperlive-cpu.nomad.hcl", # may not be needed in cloud
    "db-migrate.nomad.hcl"
  ])

  deployment_jobs = setsubtract(local.all_job_files, local.excluded_jobs)
}

resource "nomad_job" "redis" {
  count   = contains(local.deployment_jobs, "redis.nomad.hcl") ? 1 : 0
  jobspec = file("../../jobs/redis.nomad.hcl")

  depends_on = [
    nomad_variable.database,
    nomad_variable.admin_api
  ]
}

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

resource "nomad_job" "whisperlive_services" {
  for_each = toset([
    "whisperlive-gpu.nomad.hcl",
  ])

  jobspec = contains(local.deployment_jobs, each.value) ? file("../../jobs/${each.value}") : ""

  depends_on = [
    nomad_job.redis,
    nomad_variable.database
  ]
}

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

output "nomad_ui_url" {
  value       = data.terraform_remote_state.infra.outputs.management_access_urls["nomad_ui"]
  description = "Nomad UI direct access URL"
} 
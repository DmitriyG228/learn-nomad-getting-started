terraform {
  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 1.4.19"
    }
  }
}

provider "nomad" {
  address = "http://127.0.0.1:4646"
}

# --- Variable Definitions ---

variable "admin_api_token" {
  type        = string
  description = "The secret token for the Admin API."
  sensitive   = true
}


# --- Nomad Variable Resources ---

resource "nomad_variable" "admin_api" {
  path = "secret/vexa/admin-api"

  items = {
    token = var.admin_api_token
  }
}


# --- Job Deployment Resources ---

# Get a list of all .nomad.hcl files in the ../jobs directory and exclude the cpu job
locals {
  all_job_files    = fileset("../jobs", "*.nomad.hcl")
  excluded_job_files = toset(["whisperlive-cpu.nomad.hcl"])
  job_files        = setsubtract(local.all_job_files, local.excluded_job_files)
}

# Create a nomad_job resource for each file
resource "nomad_job" "vexa_services" {
  for_each = local.job_files

  jobspec = file("../jobs/${each.value}")

  # This ensures the jobs are deployed only after the variable is created
  depends_on = [nomad_variable.admin_api]
}

# --- Outputs ---

# Output the deployed jobs for verification
output "deployed_jobs" {
  value = {
    for job_name, job in nomad_job.vexa_services : job_name => {
      id     = job.id
      name   = job.name
      status = job.status
    }
  }
}

output "nomad_variables_managed" {
  description = "A list of Nomad variables managed by this Terraform configuration."
  value       = [nomad_variable.admin_api.path]
} 
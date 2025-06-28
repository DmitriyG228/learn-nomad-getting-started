terraform {
  required_version = ">= 1.6.0"
}

############################
# Remote state – reads outputs of infra workspace (gcp)
############################

# Using local backend path for now; replace with GCS after we move to remote backend

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../gcp/terraform.tfstate"
  }
}

############################
# Providers
############################

provider "nomad" {
  # Example output value is a full URL (http://IP:4646)
  address = data.terraform_remote_state.infra.outputs.management_access_urls["nomad_ui"]
} 
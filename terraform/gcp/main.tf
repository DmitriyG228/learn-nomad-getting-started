terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.50.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = ">= 1.4.19"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

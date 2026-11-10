terraform {
  required_version = ">= 1.10"

  # If using HCP Terraform (formerly Terraform Cloud), configure remote state here:
  # cloud {
  #   organization = "labs_successfulsuccess"
  #   workspaces {
  #     name = "successfulsuccess-gcp"
  #   }
  # }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

terraform {
  required_version = ">= 1.10"

  cloud {
    # Replace with your HCP Terraform organization name (e.g. ooad-<github-username>)
    organization = "labs_successfulsuccess"

    workspaces {
      # Replace with your workspace name (e.g. successfulsuccess-dev)
      name = "successfulsuccess-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
      ManagedBy    = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

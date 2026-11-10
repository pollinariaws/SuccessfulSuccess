# Enable all necessary Google Cloud APIs declaratively
# disable_on_destroy is set to false so destroying Terraform does not disable APIs for the whole project

locals {
  services = [
    "run.googleapis.com",                  # Cloud Run Admin API
    "sqladmin.googleapis.com",             # Cloud SQL Admin API
    "secretmanager.googleapis.com",        # Secret Manager API
    "artifactregistry.googleapis.com",     # Artifact Registry API
    "iam.googleapis.com",                  # Identity and Access Management API
    "cloudresourcemanager.googleapis.com", # Resource Manager API
    "firebase.googleapis.com",             # Firebase Management API
    "firebasehosting.googleapis.com",      # Firebase Hosting API
    "bigquery.googleapis.com",             # BigQuery API (Part 4)
    "aiplatform.googleapis.com",           # Vertex AI API (Part 4)
    "documentai.googleapis.com",           # Document AI API (Part 4)
    "vision.googleapis.com",               # Cloud Vision API (Part 4)
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(locals.services)

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

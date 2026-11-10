locals {
  # If container_image is provided, use it; otherwise construct from Artifact Registry repository
  image_uri = var.container_image != "" ? var.container_image : "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}/${var.app_name}-api:${var.image_tag}"

  labels = {
    project     = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

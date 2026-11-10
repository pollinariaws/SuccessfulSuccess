# Artifact Registry repository for container images
resource "google_artifact_registry_repository" "backend" {
  depends_on = [google_project_service.apis]

  location      = var.region
  repository_id = "${var.app_name}-backend"
  description   = "Docker container repository for Spry backend API"
  format        = "DOCKER"

  labels = local.labels
}

# Service account dedicated strictly to the Cloud Run API runtime
resource "google_service_account" "api" {
  depends_on = [google_project_service.apis]

  account_id   = "${var.app_name}-api"
  display_name = "Cloud Run Spry API Service Account"
  description  = "Least-privilege runtime identity for Spry backend API"
}

# Grant Cloud SQL Client permission to connect via Cloud SQL Auth Proxy / Unix domain socket
resource "google_project_iam_member" "api_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Grant Secret Manager Secret Accessor to read secrets at runtime
resource "google_project_iam_member" "api_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Grant Log Writer to stream logs to Google Cloud Logging
resource "google_project_iam_member" "api_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api.email}"
}

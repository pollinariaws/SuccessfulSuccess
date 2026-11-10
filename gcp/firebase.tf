# Enable Firebase features for the Google Cloud project
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.apis]
}

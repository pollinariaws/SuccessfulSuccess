output "cloud_run_url" {
  description = "The HTTPS URL of the deployed Cloud Run API service"
  value       = google_cloud_run_v2_service.api.uri
}

output "artifact_registry_repository" {
  description = "Artifact Registry Docker repository name"
  value       = google_artifact_registry_repository.backend.name
}

output "artifact_registry_image_uri" {
  description = "Target image URI for pushing the backend container"
  value       = local.image_uri
}

output "cloud_sql_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "cloud_sql_connection_name" {
  description = "Connection name of the Cloud SQL instance (<project>:<region>:<instance>)"
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloud_sql_public_ip" {
  description = "Public IPv4 address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "api_service_account_email" {
  description = "Email of the dedicated service account the API runs as"
  value       = google_service_account.api.email
}

output "db_name" {
  description = "Name of the database"
  value       = google_sql_database.meetings.name
}

output "db_user" {
  description = "Database username"
  value       = google_sql_user.app_user.name
}

output "stop_database_command" {
  description = "gcloud CLI command to stop the Cloud SQL instance and pause compute billing"
  value       = "gcloud sql instances patch ${google_sql_database_instance.postgres.name} --activation-policy NEVER --project ${var.project_id}"
}

output "start_database_command" {
  description = "gcloud CLI command to start the Cloud SQL instance"
  value       = "gcloud sql instances patch ${google_sql_database_instance.postgres.name} --activation-policy ALWAYS --project ${var.project_id}"
}

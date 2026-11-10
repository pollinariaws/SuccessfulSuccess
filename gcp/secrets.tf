# Generate a cryptographically secure, URL-safe password for the PostgreSQL user
resource "random_password" "db_password" {
  length  = 24
  special = false # Ensures no URL escaping bugs in DATABASE_URL
}

# Secret Manager secret for database password
resource "google_secret_manager_secret" "db_password" {
  depends_on = [google_project_service.apis]

  secret_id = "${var.app_name}-db-password"

  replication {
    auto {}
  }

  labels = local.labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Secret Manager secret for full DATABASE_URL connection string
resource "google_secret_manager_secret" "database_url" {
  depends_on = [google_project_service.apis]

  secret_id = "${var.app_name}-database-url"

  replication {
    auto {}
  }

  labels = local.labels
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgresql+asyncpg://${var.db_user}:${random_password.db_password.result}@/${var.db_name}?host=/cloudsql/${google_sql_database_instance.postgres.connection_name}"
}

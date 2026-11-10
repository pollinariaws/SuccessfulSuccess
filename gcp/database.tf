resource "random_id" "db_suffix" {
  byte_length = 4
}

# Cloud SQL for PostgreSQL (db-f1-micro)
resource "google_sql_database_instance" "postgres" {
  depends_on = [google_project_service.apis]

  # GCP reserves deleted instance names for up to 7 days; random suffix prevents naming collisions
  name             = "${var.app_name}-pg-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_16"
  region           = var.region

  # Important for student labs: allow terraform destroy to cleanly remove the database
  deletion_protection = false

  settings {
    tier              = var.db_tier # db-f1-micro (shared core, 0.6 GB RAM)
    availability_type = "ZONAL"     # Single zone to minimize costs (not REGIONAL HA)
    disk_size         = 10          # Smallest 10 GB SSD
    disk_type         = "PD_SSD"
    disk_autoresize   = false # Prevent disk from growing and raising storage bills

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled    = false # Minimal lab cost; no automated backup storage charges
      start_time = "03:00"
    }

    user_labels = local.labels
  }
}

# PostgreSQL application database
resource "google_sql_database" "meetings" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

# PostgreSQL application user
resource "google_sql_user" "app_user" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
}

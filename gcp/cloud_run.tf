# Cloud Run Service (v2) for Spry Backend API
resource "google_cloud_run_v2_service" "api" {
  depends_on = [
    google_project_service.apis,
    google_project_iam_member.api_cloudsql,
    google_project_iam_member.api_secret_accessor,
    google_project_iam_member.api_log_writer,
    google_sql_database_instance.postgres,
    google_sql_database.meetings,
    google_sql_user.app_user,
    google_secret_manager_secret_version.database_url,
  ]

  name     = "${var.app_name}-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = 0 # Scales to zero when idle
      max_instance_count = 5
    }

    containers {
      image = local.image_uri

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true # CPU only allocated during request processing
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "APP_TIMEZONE"
        value = var.app_timezone
      }

      env {
        name  = "CORS_ORIGINS"
        value = var.cors_origins
      }

      env {
        name  = "RUN_MIGRATIONS_ON_START"
        value = "true"
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.postgres.connection_name]
      }
    }
  }

  labels = local.labels
}

# Allow unauthenticated access so the frontend and API clients can call endpoints
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

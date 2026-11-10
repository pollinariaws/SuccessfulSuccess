variable "project_id" {
  type        = string
  description = "The globally unique Google Cloud Project ID (e.g. spry-polina-2026)"
}

variable "region" {
  type        = string
  description = "The Google Cloud region to deploy resources into"
  default     = "us-central1"
}

variable "app_name" {
  type        = string
  description = "Prefix and application name used across GCP resources"
  default     = "successfulsuccess"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier (smallest shared-core db-f1-micro)"
  default     = "db-f1-micro"
}

variable "db_name" {
  type        = string
  description = "Name of the PostgreSQL database"
  default     = "meetings"
}

variable "db_user" {
  type        = string
  description = "Name of the PostgreSQL application user"
  default     = "app"
}

variable "container_image" {
  type        = string
  description = "Full Docker image URI in Artifact Registry. If empty, local.image_uri is used"
  default     = ""
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy if container_image is not fully specified"
  default     = "latest"
}

variable "app_timezone" {
  type        = string
  description = "Timezone string for date/time computations"
  default     = "Europe/Kyiv"
}

variable "cors_origins" {
  type        = string
  description = "Comma-separated list of allowed CORS origins, or * for all"
  default     = "*"
}

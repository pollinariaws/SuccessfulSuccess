variable "project_name" {
  type        = string
  description = "Prefix for the names of resources in this project"
  default     = "successfulsuccess"
}

variable "region" {
  type        = string
  description = "AWS Region to deploy resources into"
  default     = "eu-north-1"
}

variable "app_urls" {
  type        = list(string)
  description = "Callback and logout URLs for Cognito, each ending with a slash"
  default     = ["http://localhost:3000/"]
}

variable "google_client_id" {
  type        = string
  description = "OAuth client ID of Google Cloud Web application client"
  default     = ""
}

variable "google_client_secret" {
  type        = string
  description = "OAuth client secret of Google Cloud Web application client"
  default     = ""
  sensitive   = true
}

# --- Optional overrides (or read automatically from backend/ecr stacks) ---

variable "vpc_id" {
  type        = string
  description = "VPC ID for Lambda VPC configuration (optional if backend stack exists)"
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Lambda VPC configuration (optional if backend stack exists)"
  default     = []
}

variable "route_table_id" {
  type        = string
  description = "Route table ID for S3 gateway endpoint (optional if backend stack exists)"
  default     = ""
}

variable "security_group_id" {
  type        = string
  description = "Security group ID for Lambda (optional if backend stack exists)"
  default     = ""
}

variable "database_url" {
  type        = string
  description = "Database connection string for report builder"
  default     = ""
  sensitive   = true
}

variable "image_uri" {
  type        = string
  description = "Docker image URI in ECR for Lambda functions"
  default     = ""
}

variable "image_tag" {
  type        = string
  description = "Image tag to use if image_uri is constructed dynamically"
  default     = "latest"
}

variable "architecture" {
  type        = string
  description = "Architecture for Lambda functions"
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be either x86_64 or arm64."
  }
}

variable "app_timezone" {
  type        = string
  description = "Application timezone for reports"
  default     = "Europe/Kyiv"
}

variable "mail_from" {
  type        = string
  description = "Verified SES sender email address"
  default     = ""
}

variable "mail_to" {
  type        = string
  description = "Recipient email address for reports"
  default     = ""
}

variable "schedule_expression" {
  type        = string
  description = "EventBridge Scheduler schedule expression"
  default     = "cron(0 7 ? * MON *)"
}

variable "schedule_timezone" {
  type        = string
  description = "Timezone for EventBridge Scheduler"
  default     = "Europe/Kyiv"
}

variable "cors_origins" {
  type        = list(string)
  description = "Allowed origins for Agenda Parser Lambda Function URL CORS"
  default     = ["*"]
}

variable "parser_model" {
  type        = string
  description = "Bedrock Foundation Model identifier for the agenda parser"
  default     = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "bedrock_region" {
  type        = string
  description = "AWS region for Bedrock service call"
  default     = "eu-north-1"
}

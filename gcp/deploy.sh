#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Spry GCP Core Deployment Helper
# Builds backend, pushes to Artifact Registry, deploys frontend to Firebase
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read project_id and outputs from Terraform
PROJECT_ID="${1:-${GCP_PROJECT_ID:-}}"
if [ -z "${PROJECT_ID}" ]; then
  if command -v terraform >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/terraform.tfvars" ]; then
    PROJECT_ID=$(cd "${SCRIPT_DIR}" && terraform output -raw project_id 2>/dev/null || grep -E '^\s*project_id\s*=' terraform.tfvars | head -n1 | cut -d'=' -f2 | tr -d ' "')
  fi
fi

if [ -z "${PROJECT_ID}" ]; then
  echo "Error: GCP Project ID is required."
  echo "Usage: ./gcp/deploy.sh <GCP_PROJECT_ID>"
  exit 1
fi

REGION="us-central1"
APP_NAME="successfulsuccess"
REPO_NAME="${APP_NAME}-backend"
IMAGE_NAME="${APP_NAME}-api"
IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || echo "latest")"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_LATEST="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:latest"

echo "======================================================================"
echo "Deploying ${APP_NAME} to Google Cloud (${PROJECT_ID} in ${REGION})"
echo "======================================================================"

# 1. Authenticate Docker with Artifact Registry
echo "--> Configuring Docker credentials for Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# 2. Build and push backend container image
echo "--> Building backend container image..."
docker build -t "${IMAGE_URI}" -t "${IMAGE_LATEST}" "${ROOT_DIR}/backend"

echo "--> Pushing backend container to Artifact Registry..."
docker push "${IMAGE_URI}"
docker push "${IMAGE_LATEST}"

# 3. Apply Terraform to ensure Cloud Run and Cloud SQL are provisioned
echo "--> Applying Terraform in gcp/..."
cd "${SCRIPT_DIR}"
terraform init
terraform apply -var="project_id=${PROJECT_ID}" -var="image_tag=${IMAGE_TAG}" -auto-approve

CLOUD_RUN_URL=$(terraform output -raw cloud_run_url)
echo "Cloud Run API deployed at: ${CLOUD_RUN_URL}"

# 4. Build and export frontend
echo "--> Building static frontend export against ${CLOUD_RUN_URL}..."
cd "${ROOT_DIR}"
rm -rf frontend/out
if command -v docker >/dev/null 2>&1; then
  docker build --target export --output type=local,dest=frontend/out \
    --build-arg NEXT_PUBLIC_API_BASE_URL="${CLOUD_RUN_URL}" \
    ./frontend
elif command -v npm >/dev/null 2>&1; then
  cd frontend
  NEXT_PUBLIC_API_BASE_URL="${CLOUD_RUN_URL}" NEXT_OUTPUT=export npm run build
  cd "${ROOT_DIR}"
fi

# 5. Deploy to Firebase Hosting
echo "--> Deploying static export to Firebase Hosting..."
if command -v firebase >/dev/null 2>&1; then
  firebase deploy --only hosting --project "${PROJECT_ID}"
else
  echo "Firebase CLI not found. Install via 'npm install -g firebase-tools' and run:"
  echo "  firebase deploy --only hosting --project ${PROJECT_ID}"
fi

echo "======================================================================"
echo "Deployment Complete!"
echo "Cloud Run API: ${CLOUD_RUN_URL}"
echo "Health check: ${CLOUD_RUN_URL}/health"
echo "To stop Cloud SQL when idle:"
echo "  gcloud sql instances patch \$(terraform -chdir=gcp output -raw cloud_sql_instance_name) --activation-policy NEVER --project ${PROJECT_ID}"
echo "======================================================================"

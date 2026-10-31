# Usage, from the repository root:  source infra/tf-env.sh
set -a
source ./.env
set +a
export TF_VAR_google_client_id="$GOOGLE_CLIENT_ID"
export TF_VAR_google_client_secret="$GOOGLE_CLIENT_SECRET"
export AWS_REGION=eu-north-1
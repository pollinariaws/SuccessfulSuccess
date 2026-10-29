#!/usr/bin/env bash
# Agenda parser helper, called by the Makefile.
#   ai.sh deploy     deploy the stack
#   ai.sh destroy    delete the stack
set -euo pipefail

aws() { $AWS_CLI "$@"; }
output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text | tr -d '[:space:]'
}
STACK="${PROJECT_NAME}-ai"

case "${1:-}" in
  deploy)
    repo=$(output "$ECR_STACK" RepositoryUri)
    digest=$(aws ecr describe-images --repository-name "${repo#*/}" \
      --image-ids imageTag="$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text | tr -d '[:space:]')
    pool=$(output "$AUTH_STACK" UserPoolId)
    client=$(output "$AUTH_STACK" UserPoolClientId)
    site=$(output "$FRONTEND_STACK" AllowedOrigins | sed 's#/$##')
    origins="http://localhost:3000"
    if [ -n "$site" ] && [ "$site" != "None" ]; then origins="$site,$origins"; fi
    echo "image=$repo@$digest origins=$origins"
    aws cloudformation deploy \
      --stack-name "$STACK" \
      --template-file infra/ai.yml \
      --capabilities CAPABILITY_IAM \
      --no-fail-on-empty-changeset \
      --tags "PROJECT_NAME=${PROJECT_NAME}" \
      --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "ImageUri=$repo@$digest" \
        "Architecture=${AWS_LAMBDA_ARCH:-x86_64}" \
        "CognitoUserPoolId=$pool" \
        "CognitoClientId=$client" \
        "CorsOrigins=$origins"
    echo "Parser URL: $(output "$STACK" ParserUrl)"
    ;;
  destroy)
    aws cloudformation delete-stack --stack-name "$STACK"
    ;;
  *)
    echo "usage: ai.sh {deploy|destroy}"; exit 2
    ;;
esac
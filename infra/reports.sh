#!/usr/bin/env bash
# Weekly report helper, called by the Makefile.
#   reports.sh deploy      deploy the stack
#   reports.sh now WEEK    queue a report for one ISO week, e.g. 2026-W39
#   reports.sh destroy     empty the bucket and delete the stack
set -euo pipefail

aws() { $AWS_CLI "$@"; }
output() {
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text | tr -d '[:space:]'
}
STACK="${PROJECT_NAME}-reports"

case "${1:-}" in
  deploy)
    : "${MAIL_TO:?set REPORT_MAIL_TO in .env}"
    repo=$(output "$ECR_STACK" RepositoryUri)
    digest=$(aws ecr describe-images --repository-name "${repo#*/}" \
      --image-ids imageTag="$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text | tr -d '[:space:]')
    vpc=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
      --query 'Vpcs[0].VpcId' --output text | tr -d '[:space:]')
    subnets=$(aws ec2 describe-subnets \
      --filters Name=vpc-id,Values="$vpc" Name=default-for-az,Values=true \
      --query 'Subnets[].SubnetId' --output text | tr '[:space:]' ',' | sed 's/,*$//')
    rtb=$(aws ec2 describe-route-tables \
      --filters Name=vpc-id,Values="$vpc" Name=association.main,Values=true \
      --query 'RouteTables[0].RouteTableId' --output text | tr -d '[:space:]')
    sg=$(output "$APP_STACK" FunctionSecurityGroupId)
    test -n "$sg" -a "$sg" != "None" || { echo "Run make aws-deploy-backend first (it exports the security group)."; exit 1; }
    # Reuse the database address the API already runs with.
    dburl=$(aws lambda get-function-configuration --function-name "${PROJECT_NAME}-backend" \
      --query 'Environment.Variables.DATABASE_URL' --output text | tr -d '[:space:]')
    echo "vpc=$vpc subnets=$subnets route-table=$rtb image=$repo@$digest"
    aws cloudformation deploy \
      --stack-name "$STACK" \
      --template-file infra/reports.yml \
      --capabilities CAPABILITY_IAM \
      --no-fail-on-empty-changeset \
      --tags "PROJECT_NAME=${PROJECT_NAME}" \
      --parameter-overrides \
        "ProjectName=${PROJECT_NAME}" \
        "VpcId=$vpc" \
        "SubnetIds=$subnets" \
        "RouteTableId=$rtb" \
        "SecurityGroupId=$sg" \
        "ImageUri=$repo@$digest" \
        "Architecture=${AWS_LAMBDA_ARCH:-x86_64}" \
        "DatabaseUrl=$dburl" \
        "AppTimezone=${APP_TIMEZONE:-Europe/Kyiv}" \
        "MailFrom=${MAIL_FROM:-$MAIL_TO}" \
        "MailTo=$MAIL_TO" \
        "ScheduleExpression=${SCHEDULE_EXPRESSION:-cron(0 7 ? * MON *)}"
    ;;
  now)
    week="${2:-}"
    [[ "$week" =~ ^[0-9]{4}-W[0-9]{2}$ ]] || { echo "usage: make report-now WEEK=2026-W39"; exit 1; }
    url=$(output "$STACK" QueueUrl)
    aws sqs send-message --queue-url "$url" \
      --message-body "{\"week\":\"$week\",\"source\":\"sqs\"}" --query MessageId --output text
    ;;
  destroy)
    bucket=$(output "$STACK" BucketName)
    [ -z "$bucket" ] || aws s3 rm "s3://$bucket" --recursive
    aws cloudformation delete-stack --stack-name "$STACK"
    ;;
  *)
    echo "usage: reports.sh {deploy|now WEEK|destroy}"; exit 2
    ;;
esac
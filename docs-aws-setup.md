# AWS setup

- Region: eu-north-1 (us-east-1 is denied by the organization's SCP)
- IAM user: polina-admin (AdministratorAccess, access key stored locally in .env, never committed)
- Cognito stack: successfulsuccess-auth (created with `make aws-deploy-auth`)
  - User pool ID: eu-north-1_pq5YEHb9e
  - Client ID: 73pu5tvp1kk7s56dklnnqf9o08
  - Domain: successfulsuccess-988492303330.auth.eu-north-1.amazoncognito.com
- Sign-in: email + password (Google disabled)

## Deployed URLs

- Frontend (S3 + CloudFront, HTTPS): https://dy9kbglnqv2xo.cloudfront.net
- Backend (Lambda function URL, HTTPS): https://xhxvuz3heemdsxubxmo7dlmlgu0olnpw.lambda-url.eu-north-1.on.aws
- No custom domain: the lecturer said it was not required.

## Changes to the forked infrastructure

- **Database: RDS PostgreSQL instead of Aurora** (`infra/backend.yml`).
  The account is on the AWS Free plan, which rejects an Aurora cluster unless it is created
  with `WithExpressConfiguration`. A single `db.t4g.micro` RDS PostgreSQL instance is
  free-plan eligible, and the rest of the template (VPC, security groups, `DATABASE_URL`)
  stays the same. Unlike the Aurora setup, this database does not pause when idle.
- **CloudFront: WAF only on the Free pricing plan** (`infra/frontend.yml`).
  A CloudFront WAF web ACL can only be created in us-east-1, but the stack runs in
  eu-north-1 (CloudFormation is denied in us-east-1 by an organization policy).
  The web ACL is now created only when `PricingPlan=FREE`. AWS refuses that plan for
  accounts on the Free Tier, so `.env` sets `AWS_CLOUDFRONT_PLAN=PAY_AS_YOU_GO`.
- **Backend on Lambda, not ECS + ALB**: this is how the forked repository is built.

## CI and deployment

- CI (`.github/workflows/style.yml`) runs on every push to `main`: ruff, ESLint and the
  backend tests against a Postgres service container.
- The backend image is tagged with the commit (`git describe`), not `latest`.
  Lambda is deployed by image digest, so the tag documents which commit was built.
- Deployment is done by running the Makefile targets locally:
  `make aws-deploy-backend` and `make aws-deploy-frontend`.
- CORS on the API is limited to the CloudFront origin (`CORS_ORIGINS`).

## Limitation: OIDC for GitHub Actions is blocked

A service control policy of the organization (`p-m72iv63d`) denies all IAM actions on
OpenID Connect providers (`CreateOpenIDConnectProvider`, `ListOpenIDConnectProviders`,
`GetOpenIDConnectProvider`) for this account. Because of that, GitHub Actions cannot get
temporary AWS credentials, and the push-to-deploy step (CD) is not enabled.
Long-lived access keys were deliberately not added to GitHub Secrets.

The intended setup, once the restriction is lifted: an OIDC provider and an IAM role whose
trust policy only accepts this repository and the `main` branch, and a workflow that calls
the same `make aws-deploy-*` targets with `aws-actions/configure-aws-credentials@v4`.

## Teardown

Run `make aws-destroy` when the work has been reviewed. The RDS instance is billed
continuously while the stack exists.

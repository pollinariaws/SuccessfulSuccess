# AWS setup

- Region: eu-north-1 (us-east-1 is denied by the organization's SCP)
- IAM user: polina-admin (AdministratorAccess, access key stored locally in .env, never committed)
- Cognito stack: successfulsuccess-auth (created with `make aws-deploy-auth`)
  - User pool ID: eu-north-1_pq5YEHb9e
  - Client ID: 73pu5tvp1kk7s56dklnnqf9o08
  - Domain: successfulsuccess-988492303330.auth.eu-north-1.amazoncognito.com
- Sign-in: email + password (Google disabled)

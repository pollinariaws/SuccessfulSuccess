7. Migrate Core Infrastructure from CloudFormation to Terraform

Date: 2026-10-31

Status

Accepted

Context

In Labs 4, 5, and 6, our project's infrastructure components were deployed using individual AWS CloudFormation templates:

infra/auth.yml: Cognito User Pool, Google Identity Provider, App Client, and Managed Login domain/branding.
infra/reports.yml: S3 reports bucket, SQS request queue & DLQ, VPC Endpoint, EventBridge weekly schedule, and report builder/mailer Lambda functions.
infra/ai.yml: Bedrock Claude agenda parser Lambda function, IAM execution policies, and public Function URL with CORS.

While functional, managing infrastructure through disparate CloudFormation stacks revealed significant limitations as the application evolved:

Multi-Provider & Multi-Cloud Boundaries: CloudFormation is strictly bound to AWS. Our architecture interacts with external resources—including Google Cloud OAuth credentials, GitHub repository secrets/actions, and multi-cloud targets. CloudFormation cannot unify these in a single declaration or execution plan.
Circular Dependencies & Workarounds: In infra/reports.yml, creating the S3 bucket and configuring event notifications required a pre-computed bucket name and DependsOn: MailerPermission hack to avoid CloudFormation's circular dependency graph.
Drift & Visibility: CloudFormation drift detection is manual, slow, and separate from deployments. It does not provide continuous, pre-deployment visual diffs (plan).
Environment Isolation & Scalability: Parameterizing environments across dev, stage, and prod with CloudFormation required orchestrating shell scripts with stack naming conventions rather than clean, module-based state separation.
Decision

We migrate infra/auth.yml, infra/reports.yml, and infra/ai.yml to HashiCorp Terraform managed through HCP Terraform (formerly Terraform Cloud) with remote state and dynamic AWS OIDC authentication.

Why Terraform (and not CloudFormation, AWS CDK, or OpenTofu)?
Over CloudFormation: Terraform provides cross-cloud provider integration (AWS, Google Cloud, GitHub), declarative dependency management that naturally solves S3-Lambda circular dependencies via separated resources (aws_s3_bucket, aws_lambda_permission, aws_s3_bucket_notification), and a mandatory, explicit execution plan before changes are applied.
Over AWS CDK: CDK introduces imperative synthesis layers (TypeScript/Python transpiling to CloudFormation YAML), retaining CloudFormation's deployment engine, rollback quirks, and AWS-only lock-in, while adding language runtime dependencies to infrastructure reviews. Terraform's HCL is declarative, language-agnostic, and has first-class state inspection.
Over OpenTofu: While OpenTofu is a capable open-source fork, our team selected Terraform to leverage HCP Terraform’s turnkey remote execution, automated VCS pull-request speculative plans, state locking, and native OIDC dynamic provider credentials out-of-the-box without maintaining self-hosted runner infrastructure.
Who can change infrastructure, and how?
No Direct Laptop Applies: Developers no longer run terraform apply locally with admin AWS credentials. The Makefile exposes only preview targets (make infra-plan, make infra-validate).
PR-Based Workflow:
An engineer (or AI assistant) drafts infrastructure changes in HCL in a Git branch.
Opening a Pull Request triggers HCP Terraform via GitHub VCS integration, generating a speculative terraform plan check on the PR.
Team members review the diff (+, ~, -).
Merging the PR to main automatically triggers terraform apply within HCP Terraform.
Authentication via Short-Lived OIDC: HCP Terraform assumes an IAM role (hcp-terraform-<org>) via dynamic AWS STS Web Identity tokens (aws.workload.identity). No long-lived AWS access keys are stored in GitHub or HCP Terraform.
Where do secrets end up (state included)?
Sensitive Variables: Secrets like google_client_secret and database_url are marked with sensitive = true in Terraform. They are injected as sensitive variables in the HCP Terraform workspace settings, never checked into Git or printed in CLI plan logs.
State Storage & Security: The Terraform state (.tfstate) contains resource attributes, which can include sensitive values. The state is centrally stored and encrypted at rest (AES-256) inside HCP Terraform, protected by workspace RBAC and TLS in transit. Local copies of state files (terraform.tfstate*) are gitignored and deleted after migration.
What happens if HCP Terraform is down?
Emergency Break-Glass Procedure:
The Terraform code remains fully portable in Git.
In a catastrophic HCP Terraform outage where an urgent production fix is required, an authorized engineer with temporary break-glass AWS credentials can reconfigure the backend in versions.tf to use a local or temporary S3 backend (terraform init -reconfigure), run terraform plan, apply the fix, and synchronize state back once HCP Terraform resumes service.
The runtime application in AWS continues operating unaffected since AWS does not depend on HCP Terraform for ongoing execution.
Consequences
Positive
Zero Downtime Adoption: Existing AWS resources (Cognito User Pool, S3 Reports Bucket, Lambda functions) are adopted intact via Terraform 1.5+ import blocks without deleting data or re-creating resources.
Resolved Dependencies: The S3 notification circular dependency is cleanly broken into modular, decoupled resources.
Auditability & Review: Every infrastructure modification has a plan attached to a Git commit and pull request.
Multi-Environment Ready: Future environments (staging, production) can be created by attaching new HCP Terraform workspaces pointing to the same repository with distinct .tfvars.
Negative / Trade-offs
State Management Overhead: Terraform state must be protected against corruption and concurrency collisions (mitigated by HCP Terraform's automatic remote locking).
Two Deployment Roads: Infrastructure deploys through HCP Terraform on git merge, whereas application code (Docker image builds and frontend exports) continues deploying through GitHub Actions / Makefile scripts. Changes requiring both (e.g. adding a new environment variable) must sequence infrastructure deployment first, followed by application deployment.
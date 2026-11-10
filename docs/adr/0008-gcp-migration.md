# 8. Migrate Core of Spry to Google Cloud Platform (Multi-Cloud Architecture & Service Mapping)

Date: 2026-11-10

## Status

Accepted

## Context

Following the migration to Terraform in Lab 7, our production infrastructure runs on AWS (Lambda, Aurora Serverless v2 PostgreSQL, S3, CloudFront, Cognito, EventBridge, SQS, Bedrock). As architects, we face the fundamental question: **what would it take to run the same system on another cloud, and what would it cost?**

Google Cloud Platform (GCP) provides strong developer ergonomics around containerized serverless workflows (Cloud Run), unified data platforms (BigQuery, Looker Studio), and specialized AI engines. However, GCP services do not map 1:1 to AWS services in either pricing semantics, execution lifecycle, or operational overhead.

This ADR records the architectural mapping of every component of Spry from AWS to GCP, evaluates tradeoffs across compute, storage, networking, and data layers, and sets the roadmap for deploying the core application to GCP while maintaining hybrid multi-cloud continuity where practical.

---

## Service Mapping & Decisions

Below is the comparative evaluation for every component of Spry's architecture:

| Spry on AWS | On Google Cloud | What is different | Decision | Justification |
| :--- | :--- | :--- | :--- | :--- |
| **S3 + CloudFront + WAF** (Static Frontend) | **Firebase Hosting** | CDN and a managed certificate included; free tier covers 10 GB stored and 360 MB/day egress. Cloud Storage buckets alone cannot serve HTTPS on custom domains without an external HTTP(S) Load Balancer ($18+/month). | **Replace** | Firebase Hosting provides zero-cost HTTPS, global CDN caching, and direct rewrites (`/api/**` to Cloud Run), completely eliminating cross-origin (CORS) complexity and domain certificate maintenance. |
| **Lambda + Function URL** (FastAPI) | **Cloud Run** | Runs standard OCI containers, scales to zero, provides managed HTTPS URLs. No 15-minute execution limit and no Lambda adapter (`mangum` or Lambda Web Adapter) required. | **Replace** | Cloud Run is simpler and more portable. The same Dockerfile tested locally runs identically in Cloud Run, listening on `PORT`. Request-based billing scales to $0 at idle. |
| **ECR** (Elastic Container Registry) | **Artifact Registry** | Standard OCI image registry; 0.5 GB free per month, then $0.10/GB. | **Replace** | Native GCP image registry with fine-grained IAM integration for Cloud Run deployments. |
| **Aurora Serverless v2** (0–1 ACU, pauses on idle) | **Cloud SQL for PostgreSQL** (`db-f1-micro`) | Cloud SQL shared-core instances do **not** automatically pause on idle. They run and bill continuously (~$7.67/mo compute + $1.70/mo storage) unless explicitly stopped. | **Replace** | Retains strict relational SQL schema, foreign keys, and existing Alembic database migrations without modifying data access code. (See in-depth database analysis below). |
| **DynamoDB** (NoSQL alternative) | **Firestore** (Datastore/Native mode) | Serverless document database billed per read/write/GB with daily free tier (50k reads, 20k writes/day). Costs $0 when idle. | **Drop / Evaluated** | While Firestore drops idle database cost to $0, it is document-oriented (no joins, no foreign keys). Migrating to Firestore would require a complete rewrite of SQLAlchemy models, queries, and migrations. |
| **Cognito User Pool + Google IdP** | **Identity Platform / Firebase Auth** | 50,000 monthly active users (MAU) free on GCP, compared to 10,000 MAU on AWS Cognito. | **Keep on AWS for Phase 1** | For the core migration, existing JWT tokens from Cognito can be validated by Cloud Run API, minimizing the migration blast radius. Identity Platform is deferred as a stretch milestone. |
| **EventBridge Scheduler** (Weekly report) | **Cloud Scheduler** | 3 jobs free per billing account, then $0.10/job per month. Calls HTTP endpoints or Pub/Sub. | **Keep on AWS for Phase 1** | Auxiliary reporting pipeline remains on AWS during Phase 1. When moved, Cloud Scheduler will invoke Cloud Run securely via OIDC. |
| **SQS** (Report job queue & DLQ) | **Cloud Tasks / Pub/Sub** | Pub/Sub is publish-subscribe with push delivery; Cloud Tasks is targeted rate-limited task queuing. | **Keep on AWS for Phase 1** | Part of the asynchronous report pipeline, retained on AWS to keep the initial GCP deployment scoped strictly to core availability. |
| **S3 Event Notification → Lambda** | **Cloud Storage + Eventarc → Cloud Run** | Eventarc routes Cloud Storage bucket events directly into Cloud Run services. | **Keep on AWS for Phase 1** | Retained on AWS with the reporting pipeline. |
| **SES** (Simple Email Service) | **Third-party (SendGrid / Mailgun) or retain AWS SES** | Google Cloud does not provide a native SMTP/email service. | **Keep SES on AWS (Multi-cloud)** | AWS SES is production-ready, domain-verified, and cost-effective ($0.10 / 1,000 emails). Calling AWS SES cross-cloud using IAM credentials stored in GCP Secret Manager is an established multi-cloud pattern. |
| **Bedrock** (Claude 3.5 Sonnet / Haiku) | **Vertex AI** (Gemini 1.5/2.0 Flash, Model Garden Claude) | Vertex AI natively hosts Google's Gemini models and Claude via Model Garden. Gemini 1.5 Flash offers 1M token context at lower per-token cost than Bedrock Haiku. | **Keep on AWS for Phase 1** | Agenda parser works on AWS Bedrock. Moving to Vertex AI Gemini is a planned stretch goal for Phase 2. |
| **SSM Parameter Store / Secrets Manager** | **Secret Manager** | 6 active secret versions free, 10,000 access operations free per month. | **Replace** | GCP Secret Manager stores the Cloud SQL password and connection strings, natively mounted as environment variables in Cloud Run without plaintext leaks. |
| **CloudWatch Logs** | **Cloud Logging** | Automatic collection of stdout and stderr from Cloud Run containers and Cloud SQL instances. | **Replace** | Cloud Run streams logs to Cloud Logging out-of-the-box with zero configuration or agent overhead. |
| **AWS IAM Roles** | **GCP Service Accounts + IAM Roles** | Distinct service account identities for deployment (Terraform) and runtime (Cloud Run API). Least privilege role assignment. | **Replace** | Terraform runs with automated deployment roles; Cloud Run runs as `spry-api@<project>.iam.gserviceaccount.com` granted strictly `Cloud SQL Client` and `Secret Manager Secret Accessor`. No long-lived keys. |
| **Terraform `aws` provider** | **Terraform `google` provider** | Same declarative HCL syntax and HCP Terraform workflow, but targeting GCP resources in an independent workspace. | **Replace** | Managed in a clean `gcp/` directory with independent state to prevent blast radius across clouds. |

---

## In-Depth Architectural Decisions

### 1. The Database: Cloud SQL vs. Firestore vs. Cross-Cloud Aurora

We evaluated four database deployment strategies:

| Option | Monthly Cost (Idle / Student) | Latency | Code & Schema Impact | Operational Overhead |
| :--- | :--- | :--- | :--- | :--- |
| **A. Cloud SQL (`db-f1-micro`) Running 24/7** | **~$9.37 / mo** ($7.67 compute + $1.70 10GB SSD) | **1–3 ms** (same GCP region `us-central1` via unix socket) | **Zero changes**. Exact same PostgreSQL schema, SQLAlchemy ORM models, and Alembic migrations. | High cost for idle students if forgotten; requires manual deletion or stopping. |
| **B. Cloud SQL (`db-f1-micro`) Stopped at Night / Idle** | **~$3.50 – $4.90 / mo** ($1.70 storage + active hours) | **1–3 ms** when active; **1–2 minute delay** on cold restart. | **Zero changes** to application code. | Requires automated Cloud Scheduler + Cloud Functions or CLI scripts to patch instance activation policy (`ALWAYS` vs `NEVER`). |
| **C. Firestore (Native / Datastore mode)** | **$0.00 / mo** (within daily free quota: 50k reads, 20k writes) | **10–25 ms** (HTTPS/gRPC API) | **High impact**. Complete rewrite of database layer: remove relational tables, joins, and Alembic; redesign data for document storage. | Minimal. Truly serverless, zero maintenance, zero idle cost. |
| **D. Keep Aurora on AWS & Call Across Clouds** | **~$0.30 – $1.50 / mo** (Aurora pauses to 0 ACU + AWS egress) | **40–120 ms** per round-trip (cross-cloud transatlantic/transcontinental network latency). | Minimal (change connection string to public endpoint with SSL). | Severe performance degradation (N+1 queries turn a 10ms request into 500ms+); exposes DB to public internet or requires expensive Interconnect/VPN. |

**Decision for Spry:**
We choose **Option A (Cloud SQL PostgreSQL `db-f1-micro`) for deployment fidelity**, combined with **clear operational shutdown runbooks (Option B / terraform destroy)** to maintain cost discipline.
- Cloud SQL maintains 100% compatibility with Spry's existing async SQLAlchemy engine and Alembic migration scripts.
- Cross-cloud database queries (Option D) introduce unacceptable latency penalties for synchronous user interactions.
- Firestore (Option C) represents an architectural rewrite that violates our objective of demonstrating portable containerized workloads across clouds.

---

### 2. Transactional E-Mail Strategy

Google Cloud has deliberately not built a native SMTP/email service, directing customers toward partner offerings (SendGrid, Mailgun) or external services.

**Decision:**
- We adopt a **hybrid multi-cloud pattern**: we retain **AWS SES** for email delivery or integrate **SendGrid's free tier** (100 emails/day).
- **Key Storage & Security:** The API credentials (AWS SES access credentials or SendGrid API key) are stored in **Google Cloud Secret Manager** (`spry-email-credentials`).
- The Cloud Run service account is granted `roles/secretmanager.secretAccessor` on this specific secret. The credentials are dynamically injected into the container environment at runtime, ensuring no credentials appear in Git, environment files, or Terraform state.

---

### 3. Which Features We Do Not Move (and Why)

We intentionally restrict the Phase 1 GCP migration to the **usable core** (Static Frontend on Firebase Hosting, API on Cloud Run, and Relational Database on Cloud SQL). The following features are not moved:

1. **Weekly Report Pipeline (EventBridge + SQS + Lambda + SES):**
   - *Reason:* The weekly report is an asynchronous background batch job. Decoupling it keeps the primary migration focused on user-facing availability. Running reporting on AWS while core runs on GCP demonstrates legitimate multi-cloud operational separation.
2. **LLM Agenda Parser (Bedrock Claude 3.5 Sonnet / Haiku):**
   - *Reason:* The agenda parser was optimized in Lab 6 with specific prompt engineering and JSON extraction schemas tuned to Bedrock's API and IAM execution roles. Re-architecting this component to Vertex AI Gemini is an isolated cognitive task designated as a stretch goal.
3. **Cognito User Pools (Authentication Identity Provider):**
   - *Reason:* Migrating user identity pools across clouds requires user password resets or complex password hash migrations. By having the Cloud Run API validate Cognito-signed JWT tokens using public JWKS keys (`https://cognito-idp.<region>.amazonaws.com/<pool-id>/.well-known/jwks.json`), our frontend and backend maintain complete identity compatibility without user disruption.

---

## Consequences

### Positive
- **Standardized Container Execution:** Eliminating the AWS Lambda Web Adapter (`run.sh` / `mangum`) allows the exact same Docker container used locally to execute in Cloud Run without proprietary wrappers.
- **Unified Origin & Zero CORS:** Firebase Hosting rewrites `/api/**` directly to Cloud Run, providing clean same-origin HTTP requests, SSL certificate management, and edge caching out of the box.
- **Portability Verification:** We prove that Spry's core application logic is decoupled from cloud vendor lock-in.

### Negative & Trade-offs
- **Idle Billing vs Serverless Pausing:** Unlike Aurora Serverless v2 which pauses to 0 ACU ($0/h) when idle, Cloud SQL bills continuously ($0.0105/h) while provisioned. Students must remember to stop or destroy the instance.
- **Multi-Cloud State Management:** Maintaining separate Terraform workspaces for AWS (`infra/`) and GCP (`gcp/`) requires managing credentials and state across two cloud provider ecosystems.

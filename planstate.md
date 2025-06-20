# Project Context
This document is **the canonical source of truth** for the "Vexa → GCP" migration. Reading only this file should be enough to understand:
1. _Why_ the project exists (objective)
2. _What_ we are building (services & architecture)
3. _How_ we will get there (roadmap phases)
4. _Key decisions/assumptions_ made so far

## Objective
Deploy the containerised services defined in `vexa/docker-compose.yml` to **production on Google Cloud Platform**. Infrastructure will be provisioned with **Terraform** and runtime orchestration handled by **HashiCorp Nomad** (with Consul & Traefik). The end-state must support horizontal scaling of real-time transcription workloads and minimise day-2 operations burden.

## Constraints & Guidelines
• Team has limited Nomad experience → favour incremental rollout, rely on official docs & best-practice templates.<br/>
• Always work in **minimum-viable phases**; each phase has an objective, implementation plan, and smoke test.<br/>
• All important decisions are captured in this file. Update immediately after each decision.

## Current Phase
- Phase 3 — Nomad & Consul Cluster (core networking complete; learning cluster under validation)

**Learning Cluster Note:** The Nomad cluster currently being provisioned is for experimentation and operator familiarisation only. It will be torn down or re-provisioned once container environment abstraction (Phase 1.5) is complete.

**Phase 1 Decision:** Skipped remote state backend for lean startup (Rule 2.1). Using local state with single operator until collaboration needs emerge.

## CRITICAL RISK IDENTIFIED 🚨
**Docker-Compose → Nomad Migration Feedback Loop (Rule 2.3)**

Current roadmap creates expensive rebuild cycles:
1. **Container Environment Mismatch**: Docker-compose services expect Docker networking (`redis:6379`, `postgres:5432`) but Nomad uses Consul service discovery (`.service.consul`)
2. **Heavy Feedback Loop**: Phase 5 builds images → Phase 6 discovers incompatibility → rebuild images → rebuild infrastructure → repeat
3. **Previous Attempt Killer**: This exact cycle caused previous migration attempts to fail

**Proposed Solution**: Insert **Phase 1.5 - Environment Abstraction**
- Create environment-agnostic configuration layer (12-factor app compliance)
- Use environment variables for all service endpoints
- Test dual-compatibility (docker-compose AND Nomad) before building production images
- **Validation**: Same image works in both docker-compose and Nomad environments

## Key Architectural Decisions (KADs)
| ID | Decision | Rationale |
|----|----------|-----------|
| KAD-01 | Use **Nomad** (not Kubernetes/MIG only) as primary orchestrator | Matches objective, lighter than k8s, consistent control plane |
| KAD-02 | **Cloud SQL (Postgres)** for stateful DB | Managed backups, HA, reduces ops toil |
| KAD-03 | **Redis runs as a Nomad job** with AOF persistence | Data is important but recreate-able; avoids Memorystore cost; keeps single orchestration surface |
| KAD-04 | **Traefik** as HTTP ingress within Nomad | Already used in compose; integrates with Consul service tags |
| KAD-05 | Container images stored in **Artifact Registry** | Regional, IAM-controlled, trivial gcloud auth |
| KAD-06 | Secrets/connection strings via **Vault or Consul KV** templates | Decouple from image, rotate safely |
| KAD-07 | Scaling strategy: Nomad Autoscaler for bots & WhisperLive; fallback to MIG if Autocaler proves unfit | Balances learning curve with operational risk |
| KAD-08 | **`bot-manager` to use Parameterized Jobs** | `bot-manager` spawns transient `vexa-bot` containers. To make these compatible with Nomad's scheduler and avoid Docker-in-Docker complexities, `bot-manager` will be refactored. It will call the Nomad API to dispatch a parameterized `vexa-bot` batch job when running in a Nomad environment, while retaining its original Docker socket behavior for local `docker-compose` development. This ensures dual-compatibility and a single orchestration control plane in production. |

## Service Inventory (derived from `docker-compose.yml`)
| Service | Type | Ports | Notes |
|---------|------|-------|-------|
| api-gateway | stateless | 8000 | Depends on admin-api, bot-manager, collector |
| admin-api | stateful-ish | 8001 | Uses Postgres & Redis |
| bot-manager | stateless; CPU heavy | 8080 + Docker socket | Spawns transient bot containers; needs Redis & Postgres. **See KAD-08**. |
| transcription-collector | stateless + background tasks | 8000 | Consumes Redis streams, writes Postgres |
| redis (Nomad job) | in-memory data | 6379 | AOF persistence, single node (replication TBD) |
| postgres (Cloud SQL) | relational | 5432 | Private IP, automated backups |
| whisperlive-gpu | GPU heavy | 9090/9091 | ≈10 sessions per instance; GPU scheduling via Nomad |
| whisperlive-cpu | CPU fallback | 9090/9091 | Profile 'cpu'; not auto-started |
| traefik | ingress | 80/8080 | Exposes internal services via domain rules |

Bots launched by **bot-manager** run as sibling Docker containers inside the same Nomad client host (initially). They scale linearly with active sessions.

## Project Roadmap – Deploy Vexa Services on GCP with Terraform & Nomad

## Overview
This roadmap is an executable plan to move the `docker-compose.yml` services to a production-grade deployment on Google Cloud Platform (GCP) orchestrated by HashiCorp Nomad and provisioned with Terraform.  Each phase is intentionally small, independently verifiable, and chained in logical order.

## Authoritative References
- HashiCorp Nomad Production Install on GCE: https://developer.hashicorp.com/nomad/tutorials/production/production-install
- Terraform Backend: Google Cloud Storage (GCS): https://developer.hashicorp.com/terraform/language/settings/backends/gcs

## Phase 0 — Roadmap Kick-off (completed ✅)
• **Objective:** Establish planning artefacts and baseline architecture decisions.<br/>
• **Implementation Plan:**
  1. Draft and commit this roadmap (`planstate.md`) as the single source of truth.
  2. Collect authoritative references for Nomad + GCP best practices (docs, tutorials, community modules).
• **Validation (Smoke-test):** File committed in repo and reviewed/accepted.

## Phase 1 — Terraform Bootstrap
• **Objective:** Prepare Terraform backend and provider configuration for GCP.
• **Implementation Plan:**
  1. Enable required APIs in the target GCP project (Compute, Artifact Registry, Cloud SQL, etc.).
  2. Create a versioned GCS bucket for remote Terraform state.
  3. Configure backend and provider blocks; run `terraform init` with remote state.
• **Validation:** `terraform init` completes without errors and state file stored in GCS.

**ROADMAP PIVOT (2025-06-19):** To accelerate development and de-risk the migration, we are adopting a **local-first** approach. We will translate the entire `docker-compose.yml` stack to run on a local Nomad agent *before* provisioning the cloud environment. This isolates the complex task of writing job specifications from infrastructure deployment.

## Phase 1.5 — Environment Abstraction
• **Objective:** Create an environment-agnostic configuration layer for all application services.
• **Implementation Plan:**
  1. Refactor all services to read connection strings (Postgres, Redis, etc.) from environment variables.
  2. Validate the full stack runs correctly via `docker-compose up`.
  3. Create a test Nomad job to validate that a container can connect to services managed by Docker Compose.
• **Validation (Smoke-test):**
  • Application stack is stable with `docker-compose up` and new `.env.compose` file.
  • A test Nomad job running on a local agent can successfully connect to the database and Redis.

**Phase 1.5 Status (2025-06-19):**
- **COMPLETED ✅:** Service refactoring is complete and validated under `docker-compose`. The final validation step (local Nomad job) was **skipped** due to a persistent, unresolvable issue with the Nomad Docker driver attempting to pull local-only images. The core objective of environment abstraction is met. We will proceed, validating Nomad connectivity in the next phase with images from a proper registry.

## Phase 2 (New) — Local Orchestration with Nomad (In Progress ⏳)
• **Objective:** Translate the entire `docker-compose.yml` into a set of Nomad job files that run locally, one by one, until the full stack is operational on Nomad.
• **Prerequisites (Completed):**
  - Docker-Compose stack is healthy and smoke-tested.
  - `bot-manager` has been refactored with a pluggable orchestrator.
• **Implementation Plan (Service Migration Checklist):**
  - [ ] **`vexa-bot.nomad`**: Create a parameterized batch job for on-demand bot instances.
  - [ ] **`nomad.py` driver**: Complete the Nomad orchestrator driver (`stop`, `status`, `verify` functions).
  - [ ] **`redis.nomad`**: Run Redis as a system job.
  - [ ] **`admin-api.nomad`**: Convert the Admin API service.
  - [ ] **`transcription-collector.nomad`**: Convert the Transcription Collector service.
  - [ ] **`bot-manager.nomad`**: Convert the Bot Manager service.
  - [ ] **`whisperlive-cpu.nomad`**: Convert the WhisperLive CPU service.
  - [ ] **`api-gateway.nomad`**: Convert the API Gateway service.
  - [ ] **`traefik.nomad`**: Convert the Traefik ingress service.
• **Validation:** `nomad status` shows all jobs `running`; the application is fully functional locally using the Nomad orchestrator. The same smoke test suite used for Docker Compose passes.

## Phase 3 (New) — Advanced Local Simulation
• **Objective:** Implement and validate production-like features (load balancing, autoscaling) on the local Nomad cluster.
• **Implementation Plan:**
  1.  **Load Balancing:** Deploy Traefik as a Nomad job, configured to use Consul catalog for service discovery.
  2.  **Autoscaling:**
      -   Install and configure the Nomad Autoscaler plugin.
      -   Define a simple scaling policy for `whisperlive-cpu` based on CPU utilization.
      -   Define a simple scaling policy for `vexa-bot` based on a Redis stream metric or custom API endpoint.
  3.  **Smoke Test:**
      -   Create a synthetic load generator (e.g., a simple Python script).
      -   Validate that increased load causes the autoscaler to launch new `whisperlive` and `vexa-bot` allocations.
      -   Validate that Traefik correctly routes traffic to the new allocations.
• **Validation:** Autoscaler correctly adjusts allocation counts up and down based on load; Traefik routing remains stable.

## Phase 4 (New) — GCP Foundation with Terraform
• **Objective:** Provision the core GCP infrastructure required to host the Nomad cluster and its dependencies.
• **Implementation Plan:**
  1.  **Networking:** Provision a VPC, subnets, and essential firewall rules using the `hashicorp/network/google` Terraform module.
  2.  **Database:** Deploy a managed **Cloud SQL (Postgres)** instance with a private IP.
  3.  **Image Storage:** Create a private **Artifact Registry** repository for container images.
  4.  **Nomad Servers:** Provision a 3-node GCE instance group for the Nomad server quorum.
  5.  **Implementation Note:** Use official Terraform modules where possible to accelerate development (Rule 2.2).
• **Validation:** A test VM deployed in the VPC can successfully connect to the Cloud SQL instance. The Nomad server UI is accessible (e.g., via an IAP tunnel).

## Phase 5 (New) — CPU-Only Production Deployment
• **Objective:** Deploy the full application stack to the GCP Nomad cluster using only CPU-based workloads.
• **Implementation Plan:**
  1.  **CI/CD:** Configure a GitHub Actions workflow to build all service images, tag them, and push them to Artifact Registry.
  2.  **Nomad Clients (CPU):** Provision a GCE Managed Instance Group (MIG) for CPU-only Nomad clients. Use a startup script to have new instances automatically join the cluster.
  3.  **Job Deployment:**
      -   Update Nomad job files with production configurations (e.g., Cloud SQL connection strings from a secrets backend, not env vars).
      -   Run all jobs on the GCP cluster.
  4.  **Ingress:** Deploy the Traefik job, integrated with a GCP TCP Load Balancer to expose the `api-gateway`.
• **Validation:** The application is fully functional and accessible via its public endpoint. The staging smoke test suite passes against the GCP deployment.

## Phase 6 (New) — Hybrid GPU Production Deployment
• **Objective:** Integrate GPU workers (both on-premise and cloud-based) into the production environment.
• **Implementation Plan:**
  1.  **On-Premise GPU Worker:**
      -   Install and configure a Nomad client on the bare-metal GPU machine.
      -   Join the client to the GCP-based Nomad cluster (requires network path for gossip and RPC).
      -   Tag the node with `meta.gpu_type = "bare_metal"`.
  2.  **Cloud GPU Workers:**
      -   Provision a separate, GPU-enabled (e.g., T4 or L4) GCE Managed Instance Group for Nomad clients.
      -   Tag these nodes with `meta.gpu_type = "cloud"`.
  3.  **Job & Autoscaler Configuration:**
      -   Update the `whisperlive-gpu` job with a `constraint` to target nodes where `meta.gpu_type` is defined.
      -   Use job `affinity` to prefer the `bare_metal` worker (e.g., `affinity { attribute = "${meta.gpu_type}" value = "bare_metal" weight = 100 }`).
      -   Configure the Nomad Autoscaler to scale the cloud GPU MIG up when the bare-metal worker is at capacity or unhealthy, and scale it down first when load decreases.
• **Validation:** Under load, GPU jobs are correctly scheduled to the bare-metal machine first, then spill over to the GCP GPU instances. The system remains stable during scale-up and scale-down events.

_(Original Phases 8 and 9 for Observability and Security will follow this initial deployment)_
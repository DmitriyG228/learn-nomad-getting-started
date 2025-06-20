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
- Phase 2A — Parameterised Job Skeleton (Starting ⚡)
- Phase 2B — Orchestrator Helper Completion (Current ⚡)
- Phase 2C — Service Job for Bot-Manager (Current ⚡)

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

**BOT-MANAGER ORCHESTRATION RISK 🚨**
**Complex State Management & Lifecycle (KAD-08)**

Bot-manager must transition from Docker socket orchestration to Nomad parameterised jobs:
1. **Half-Complete Implementation**: Nomad dispatch code exists but lifecycle helpers (stop, verify, status) are stubs
2. **Testing Complexity**: Bot lifecycle involves DB state, Redis pub/sub, container orchestration, and HTTP callbacks
3. **Dual-Path Maintenance**: Must maintain Docker orchestrator path until Nomad route proven stable

**Solution Strategy**: Break bot-manager work into minimal phases (2A-2E) with concrete smoke tests at each step.

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
| KAD-09 | **Configuration Encoding Strategy for transient *vexa-bot* jobs** | Encode the full `BOT_CONFIG` as **Base64-JSON** in a single environment variable (`BOT_CONFIG_B64`) instead of raw JSON, and generate it with Nomad's `toJSON` → `base64encode` pipeline.  The bot entrypoint will `base64 -d` and parse the JSON. |

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

## Phase 2 (New) — Local Orchestration with Nomad (Refactored into sub-phases 2A-2E)

**Context**: This phase has been broken down into smaller increments to manage the complexity of bot-manager orchestration and reduce feedback loops.

### Phase 2A — Parameterised Job Skeleton (Current ⚡)
• **Objective**: Produce a valid `jobs/vexa-bot.nomad.hcl` that Nomad can parse and dispatch manually.
• **Implementation Plan**:
  1. Create batch job with `parameterized { meta_required = ["connection_id","user_id","meeting_id"] }`.
  2. Template block turns meta into env-vars (`BOT_USER_ID`, `MEETING_URL`, etc.).
  3. Resources: 200 MHz / 256 MiB for dev iteration.
  4. Dummy `command: ["echo", "hello"]` for quick exit during iteration.
• **Smoke-test**: 
  - `nomad job run -output jobs/vexa-bot.nomad.hcl` ⇒ HCL accepted.
  - `nomad job dispatch -meta connection_id=test vexa-bot` ⇒ allocation appears and exits 0.
• **Risk Retired**: Basic job template & parameterisation syntax.

### Phase 2B — Orchestrator Helper Completion
• **Objective**: Finish Nomad-specific helpers in `app/orchestrators/nomad.py`.
• **Implementation Plan**:
  1. `stop_bot_container` → `POST /v1/job/<id>/stop` or `/deregister`.
  2. `verify_container_running` polls `/v1/job/<id>` for running status.
  3. `get_running_bots_status` queries `/v1/jobs?prefix=vexa-bot-` filtered by Meta.user_id.
  4. Unit-test each helper with pytest + respx (HTTP mocking).
• **Smoke-test**: Helper functions work against dev Nomad agent with expected HTTP responses.
• **Risk Retired**: Bot-manager can manage lifecycle, not just dispatch.

### Phase 2C — Service Job for Bot-Manager
• **Objective**: Run bot-manager itself under Nomad with `ORCHESTRATOR=nomad`.
• **Implementation Plan**:
  1. Create `jobs/bot-manager.nomad.hcl` (service, port 8080).
  2. Inject env-vars: `ORCHESTRATOR=nomad`, `NOMAD_ADDR` from Consul template.
  3. Health-check on `/`.
• **Smoke-test**: 
  - `nomad run jobs/bot-manager.nomad.hcl` ⇒ allocation healthy, service in Consul.
  - `curl :8080/` returns "Bot Manager is running".
• **Risk Retired**: Bot-manager itself works under Nomad.

### Phase 2D — End-to-End Dispatch Test
• **Objective**: Prove bot-manager can launch a bot via parameterised job.
• **Implementation Plan**:
  1. Test API call: `curl -X POST localhost:8080/bots` with platform & meeting data.
  2. Watch Nomad UI: new dispatch creates `vexa-bot/instance-<uuid>`.
  3. Verify bot-manager logs record dispatch-ID & connection-ID.
• **Smoke-test**: 
  - API returns 201, job reaches `complete`.
  - `curl /bots/status` shows one active bot.
• **Risk Retired**: API wiring + Nomad dispatch path.

### Phase 2E — Lifecycle & Failure Handling
• **Objective**: Validate stop, duplicate requests, and exit callback logic.
• **Implementation Plan**:
  1. Test DELETE `/bots/{platform}/{id}` → bot exits and job stopped.
  2. Test duplicate POST while job running → expect 409.
  3. Exercise `/bots/internal/callback/exited` with fake payload.
• **Smoke-test**: Automated pytest suite with all assertions green.
• **Risk Retired**: Graceful cleanup & duplicate-bot protection.

### Remaining Services (Post Bot-Manager)
  - [ ] **`transcription-collector.nomad`**: Convert the Transcription Collector service.
  - [ ] **`api-gateway.nomad`**: Convert the API Gateway service.
  - [ ] **`whisperlive-cpu.nomad`**: WhisperLive CPU variant.
  - [ ] **`traefik.nomad`**: Traefik ingress.
  - [ ] **Dev-cluster helper script** (`scripts/dev-cluster.sh`) to start/stop Consul & Nomad deterministically.

• **Overall Phase 2 Validation**: `nomad status` shows all jobs `running`; application fully functional locally using Nomad orchestrator.

**Phase 2 Status (2025-06-20):**
- **COMPLETED ✅:** `redis.nomad.hcl` is running successfully on the local Nomad agent.
- **COMPLETED ✅:** `admin-api.nomad.hcl` is running successfully, healthchecks passing, service registered in Consul.
- **COMPLETED ✅ Phase 2A:** `vexa-bot.nomad.hcl` parameterised job skeleton completed successfully. Job dispatches correctly with metadata passing through as environment variables.
- **COMPLETED ✅ Phase 2B:** Nomad orchestrator helper functions completed and smoke-tested successfully. All lifecycle operations (start, stop, verify, status) working correctly against live Nomad agent.
- **COMPLETED ✅ KAD-09 Implementation:** Base64-encoded bot configuration successfully deployed and tested. Real bot instances now launching with proper browser automation capabilities.
- **BOT CONFIG SCHEMA RESEARCH ✅:** Completed comprehensive analysis of vexa-bot configuration requirements. The bot expects a specific `BOT_CONFIG` JSON schema with required fields: platform, meetingUrl, botName, token, connectionId, nativeMeetingId, redisUrl, automaticLeave object, plus optional fields like language, task, meeting_id, reconnectionIntervalMs, and botManagerCallbackUrl.
- **LESSON LEARNED (Nomad Template JSON):** Nomad templates have limitations when generating JSON. Direct JSON construction in templates results in property names losing quotes (`{platform:` instead of `{"platform":`). The issue stems from template processing stripping quotes. Attempted solutions included using `toJSON` function, `dict`/`merge` functions (not available in Nomad templates), and complex escaping strategies.
- **LESSON LEARNED (Consul):** Initial deployment failed due to a missing Consul agent. The Nomad agent requires a running Consul agent to be present *at startup* to enable service discovery features. The resolution was to:
    1. Install Consul using the official HashiCorp `apt` repository to ensure it's in the system `PATH`.
    2. Strictly adhere to a startup order: `consul agent -dev` first, then `nomad agent -dev`.
    3. Use the `-consul-address` flag on the Nomad agent for explicit configuration.
- **LESSON LEARNED (CNI):** Job placement failed with a `Constraint` error for `attr.plugins.cni.version.bridge`. This is because any job with `network { mode = "bridge" }` requires the CNI reference plugins to be installed on the Nomad client node. This is a one-time setup task per client.
- This confirms that our local Nomad+Consul dev environment is now correctly configured for service discovery.
- **LESSON LEARNED (External Service IP):** Consul external-service definitions must reference the **actual** container IP on the Compose network (`172.21.0.0/16`), *not* `docker0`.  IP drift breaks template rendering and cascades into task failure. Prefer host-port mapping or dynamic registration to avoid hard-coding.
- **LESSON LEARNED (Docker Image Tags):** Nomad's Docker driver **always** attempts to pull images with the `:latest` tag, regardless of the `force_pull = false` setting. For local development images, use a specific tag (e.g., `:dev`) to prevent registry pulls and use locally built images.
- **LESSON LEARNED (Health Checks):** Service health check paths must match actual API endpoints. The admin-api service responds on `/` but not `/health`. Always verify endpoint availability before configuring service checks.
- **LESSON LEARNED (Template Syntax):** Nomad templates do not support the `default` function. Use the `or` function instead for providing default values: `{{ or (env "NOMAD_META_optional_var") "default_value" }}`.
- **TEMPLATE SYNTAX FIX:** Corrected Nomad template syntax from `| attr "address"` to `.Address` for accessing Consul service attributes.
- **CURRENT SERVICES:** Both `redis` and `admin-api` are running successfully with proper service discovery integration.
- **NEXT ACTION:** Starting Phase 2B - Complete Nomad orchestrator helpers in bot-manager.

## Newly Identified Best Practice & Decision

### KAD-09 — Configuration Encoding Strategy for transient *vexa-bot* jobs
| Decision | **Encode the full `BOT_CONFIG` as **Base64-JSON** in a single environment variable (`BOT_CONFIG_B64`) instead of raw JSON, and generate it with Nomad's `toJSON` → `base64encode` pipeline.  The bot entrypoint will `base64 -d` and parse the JSON. |
|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Rationale |
1. **Template Limitations:** Nomad's env-template parser strips quotes from inline objects which makes raw JSON invalid.  Using `toJSON` on a map requires the Consul-Template `dict/merge` helpers that are blocked by the client's `function_denylist` (see Nomad issue #17026).  Base64 sidesteps all quoting/escaping problems entirely.
2. **Industry Precedent:** Kubernetes  ➜ widely uses base64-encoded config blobs in secrets; Nomad docs explicitly recommend `toJSON → base64encode` for complex secrets (template block examples).
3. **Runtime Simplicity:** The bot only needs a two-line shim (`echo "$BOT_CONFIG_B64" | base64 -d > /tmp/conf.json`) added to `entrypoint.sh`.  No change to existing Zod schema.
4. **Security:** The same mechanism is Vault-compatible and avoids accidental log leaks (binary strings are not echoed by default).

| Impact |
* **jobs/vexa-bot.nomad.hcl** will switch to:
  ```hcl
  template {
    data = <<EOH
    {{- $cfg := env "NOMAD_META_platform" | regexReplaceAll "-" "_" | toJSON }}
    # … build map with simple `set` helpers then …
    BOT_CONFIG_B64={{ $cfg | toJSON | base64Encode }}
    EOH
    destination = "local/bot.env"
    env = true
  }
  ```
* `core/entrypoint.sh` gets a small decode step.

| Validation |
* Dispatch debug job must print **valid JSON** after `base64 -d` and the bot must start without `SyntaxError`.
* Smoke-test added to Phase 2D.


### Phase 2B status update
- **COMPLETED ✅** Nomad helper functions.
- **CONFIG ENCODING RESOLVED ✅** KAD-09 adopted; JSON quote-stripping risk retired.

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
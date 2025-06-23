# Vexa Platform - Migration to Nomad

This document captures the current state of migrating the Vexa platform from a `docker-compose` setup to a robust, isolated Nomad environment.

---

## Architecture & Migration Plan

### Isolated Nomad Environment

The system is designed to run as a self-contained environment within Nomad. All service-to-service communication is handled through Consul service discovery. There are **no fallbacks** to external services; if a dependency is not available within Consul, the dependent service will fail to start, ensuring clear failure detection.

**Backward Compatibility**: The Docker images built for this environment are compatible with the original `docker-compose.yml` for local development, but the two environments (Nomad vs. Docker Compose) are not intended to be mixed at runtime.

**Example:** Service Discovery for Postgres
```hcl
# This template requires the "postgres" service to be available in Consul.
# If it is not found, the template will not render and the job will fail.
template {
  data = <<EOH
{{ with service "postgres" }}{{ with index . 0 }}DB_HOST={{ .Address }}
DB_PORT={{ .Port }}{{ end }}{{ end }}
EOH
# ...
}
```

### Externalized PostgreSQL

To mimic a managed database service, the PostgreSQL database runs in an external container (`vexa-ext-postgres`) and is not managed by Nomad. Nomad services connect to it using a fallback mechanism in their templates.

**Example:** Connecting to External Postgres
```hcl
# This template attempts to find the "postgres" service in Consul.
# If not found, it falls back to the external Docker container's address.
template {
  data = <<EOH
{{ with service "postgres" }}{{ with index . 0 }}DB_HOST={{ .Address }}
DB_PORT={{ .Port }}{{ end }}{{ else }}# Fallback to external postgres (vexa-ext-postgres)
DB_HOST=172.17.0.1
DB_PORT=5438{{ end }}
EOH
# ...
}
```

**All other services** rely exclusively on Consul service discovery within the isolated Nomad environment.

### Phase 1: Service Standardization & Isolation ✅ (COMPLETE)
**Objective**: Deploy all services from `docker-compose.yml` into a self-contained Nomad environment that connects to an external PostgreSQL database.
**Status**:
-   All necessary services have a corresponding Nomad job file in `jobs/`.
-   The `postgres.nomad.hcl` job has been removed.
-   Jobs depending on Postgres are configured to connect to the external container.
-   All other services are fully isolated within Nomad.

### Phase 2: Production Hardening 📋 (PLANNED)
**Objective**: Make the Nomad deployment robust and secure for production.
**Next Steps**:
-   **Consul Connect**: Transition all services to a full service mesh with mTLS for zero-trust security.
-   **Secrets Management**: Integrate with HashiCorp Vault for database credentials and API tokens.
-   **Resource Optimization**: Fine-tune CPU and memory resource requests and limits based on performance testing.
-   **Autoscaling**: Implement and test autoscaling policies for all stateless services.

---

## Implemented Services Overview

| Service | Nomad Job | Key Dependencies | Networking Notes |
|---|---|---|---|
| **API Gateway** | `api-gateway.hcl` | admin-api, bot-manager, transc-coll | Bridge, Consul Discovery |
| **Admin API** | `admin-api.hcl` | postgres (ext), redis | Bridge, Consul Discovery, PG Fallback |
| **Bot Manager** | `bot-manager.hcl`| postgres (ext), redis | Bridge, Consul Discovery, PG Fallback |
| **Vexa Bot** | `vexa-bot.hcl` | redis, bot-manager | Bridge, Parameterized, Consul Discovery |
| **Transcription Collector**| `transcription-collector.hcl` | postgres (ext), redis | Bridge, Consul Discovery, PG Fallback |
| **WhisperLive (GPU)** | `whisperlive-gpu.hcl`| redis | Bridge, GPU, Consul Discovery |
| **WhisperLive (CPU)** | `whisperlive-cpu.hcl`| redis | Bridge, Consul Discovery |
| **Redis** | `redis.hcl` | - | Bridge |

---

## Redis-Based WhisperLive Routing

The connection between `vexa-bot` and `whisperlive` instances remains managed by the Redis-based load balancing system, which is superior for this use case as it is session-aware.

-   **WhisperLive Instances**: On startup, each instance registers its WebSocket URL (`ws://<alloc-ip>:<port>/ws`) and current session count in a Redis sorted set (`wl:rank`).
-   **Vexa-Bot Instances**: On startup, the bot queries the `wl:rank` sorted set to find the WhisperLive instance with the lowest score (least number of sessions) and connects to it.

This self-healing and fair mechanism is preserved and enhanced by running within the isolated Nomad environment.

---

## Rationale for Key Decisions

1.  **Isolated Nomad Environment (with Exception)**: Ensures a predictable deployment, making failures fast and obvious, while allowing the database to be an external dependency.
2.  **Keep Redis Routing for WhisperLive**: This custom logic is more intelligent for its specific task than a generic service mesh load balancer.
3.  **Bridge Networking as Standard**: Ensures consistency and avoids port conflicts on the host, a requirement for scaling and service mesh.
4.  **Strict Consul for Internal Discovery**: Guarantees that all intra-Nomad communication is managed and observable.
5.  **Declarative Dependencies**: Using `template` blocks to wait for services ensures resilience and proper startup order.

---

## Critical Fixes Implemented (Rule 2.2 & 3.3)

### 1. Fixed Nomad API Address Configuration
**Issue**: `bot-manager.nomad.hcl` had hardcoded `NOMAD_ADDR = "http://192.168.1.4:4646"` which would break in cloud deployment.
**Solution**: Removed hardcoded address. The bot-manager service now uses the default Nomad agent address provided by the environment, making it portable across environments.

### 2. Fixed Platform Name Transformation
**Issue**: The `vexa-bot.nomad.hcl` template was incorrectly transforming `"google"` to `"google_meet"`, but the API already sends `"google_meet"` directly.
**Solution**: Removed obsolete transformation logic. Platform names now pass through unchanged from API to bot.

### 3. Fixed Language Auto-Detection 
**Issue**: Language was defaulting to `"en"` which prevented WhisperLive auto-detection.
**Solution**: Changed to pass `null` when no language specified, enabling WhisperLive's automatic language detection feature.

### 4. Fixed Token Handling for WhisperLive Authentication
**Issue**: User token was defaulting to empty string, but WhisperLive requires valid tokens for authentication and the transcription-collector validates all tokens against the database.
**Solution**: Changed to pass `null` when no token provided, and properly handle token validation flow through WhisperLive → Redis → transcription-collector → database.

### 5. Removed Unused DEVICE_TYPE from bot-manager
**Issue**: `DEVICE_TYPE = "cpu"` was being set in bot-manager but this configuration is only relevant for WhisperLive services.
**Solution**: Removed unused environment variable to clean up the configuration.

**Impact**: These fixes ensure proper authentication flow, enable language auto-detection, and make the deployment cloud-ready by removing hardcoded local addresses.

### 6. **CRITICAL DATABASE PORT CORRECTION** ⚠️ 
**Issue**: `admin-api.nomad.hcl` and `transcription-collector.nomad.hcl` were configured to connect to wrong database port 5438 (pointing to `vexa-postgres-1` container) instead of the correct development database `vexa-ext-postgres` on port 25432.
**Solution**: Corrected `DB_PORT=25432` in both jobs and updated Alembic configuration URL. The `bot-manager.nomad.hcl` was already correctly configured.
**Verification**: Confirmed `vexa-ext-postgres` container is running on port 25432:
```bash
docker ps --filter "name=vexa-ext-postgres"
# Shows: 0.0.0.0:25432->5432/tcp   vexa-ext-postgres
```
**Impact**: Critical security fix - ensures all Nomad services connect to the correct development database, preventing data corruption and authentication failures.

### 7. **WHISPERLIVE MEMORY ALLOCATION FIX** ⚠️ 
**Issue**: WhisperLive CPU containers were getting OOM killed with "Exit Code: 137" due to insufficient memory allocation (2048 MB).
**Solution**: Increased memory allocation from 2048 MB to 4096 MB in `whisperlive-cpu.nomad.hcl`.
**Verification**: Both WhisperLive instances now running stably without restarts. Bot logs show successful connection, language detection ("en"), and active speaker event processing.
**Impact**: Fixed bot-to-WhisperLive connection stability. Transcription pipeline now fully operational with Redis-based routing, language auto-detection, and speaker events working correctly.

---

## Docker Image Management & Container Registry ✅ (COMPLETE)

**Objective**: Ensure all Docker images are built locally and available for Nomad deployment.

### Local Image Build Infrastructure
All services from `docker-compose.yml` are now built using the root `Makefile`:

**Built Images Available:**
- `services/admin-api:dev` - Admin API service
- `services/api-gateway:dev` - API Gateway service  
- `services/vexa-bot:dev` - Bot automation service
- `services/bot-manager:dev` - Bot lifecycle management
- `services/transcription-collector:dev` - Transcription processing
- `services/whisperlive:cpu-dev` - WhisperLive CPU transcription
- `services/whisperlive:gpu-dev` - WhisperLive GPU transcription
- `services/json-debug:dev` - Debug utility

### Nomad Image Access Strategy
**Local Images (Current)**: Nomad accesses images directly from the local Docker daemon using `force_pull = false`. This works because all Nomad job files reference images like `services/vexa-bot:dev` without registry prefixes, causing Docker to use locally available images.

**Optional Local Registry**: A local Docker registry can be started with `make start-registry` and images pushed with `make push-local` for multi-node setups, but this is not required for single-node development.

### Build Commands
```bash
# Build all images locally for Nomad
make build

# Show what images are available
make show-images

# Optional: Push to local registry for multi-node
make push-local
```

**Rationale**: Local image builds ensure fast iteration during development while maintaining compatibility with both docker-compose and Nomad environments. Images are built once and used by both systems without requiring external registries.

---

*Last updated: Implemented critical production fixes for platform names, language detection, token authentication, and cloud portability.* 
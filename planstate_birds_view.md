# Vexa → Nomad on GCP  — *Strategic Plan ("planstate_fresh")*

---

## 1 • Mission Statement
Deploy every service described in `vexa/docker-compose.yml` to **production** on Google Cloud Platform using **HashiCorp Nomad** for orchestration, **Consul** for service discovery, and **Cloud SQL (Postgres)** for durable state. Workloads that require GPUs will run on a self-hosted bare-metal node, with an automatic **fallback to GCP GPU instances** when local capacity is unavailable.

---

## 2 • Guiding Principles
1. *Incremental delivery* — split the journey into small, smoke-tested milestones.
2. *12-Factor compliance* — configuration is delivered via environment variables / templates; images are environment-agnostic.
3. *Native integrations first* — prefer Nomad's own features (native service discovery, autoscaler) and Consul catalog before introducing extra tooling.
4. *Infrastructure-as-Code* — everything reproducible via Terraform (GCP) and HCL job files (Nomad).
5. *Fail-fast dev loop* — develop and validate locally before promoting changes to the cloud.
6. *Observability & reliability* — each service gets health checks; system metrics feed autoscaling decisions.

---

## 3 • Current Snapshot *(2025-06-21)*
✔ Single-node Nomad + Consul dev cluster running in Docker.
✔ Redis, Admin-API, Bot-Manager, Vexa-Bot jobs healthy.
✔ **M3 REDIS DISCOVERY SUCCESS**: WhisperLive publishes live session metric & heartbeat; Vexa-Bot dynamically selects least-loaded WL via Redis.
✔ Bot logs show: "Selected WhisperLive URL from Redis: ws://172.27.0.2:9090/ws" - Redis discovery working perfectly!
⚠️ **Current Issue**: Bot can connect to Google Meet & discover WL via Redis, but WebSocket connection to WhisperLive times out (3000ms).
✔ End-to-end smoke test passes — bot joins Google Meet, transcript visible.

> Detailed design of WhisperLive routing & autoscaling lives in [`docs/whisperlive_scaling.md`](docs/whisperlive_scaling.md).

> *Key fixes already applied:* bridge networking (avoids port clashes), **JSON-safe `BOT_CONFIG` using `printf`+`toJSON` (no Base64)**, local image tags `:dev`, CNI plugins installed.

---

## 4 • Milestone Roadmap
| ID | Goal (Smoke-test) | Key Tasks |
|----|-------------------|-----------|
| **M0** | *Local Postgres substitute ready* — `vexa-ext-postgres` container healthy | build image, create schema, expose on host `25432` |
| **M1** | *Redis service running under Nomad* — `redis-cli PING` from any task returns `PONG` | `jobs/redis.nomad.hcl`, service registration |
| **M2** | *Admin-API reachable* — `curl /` responds 200 | `jobs/admin-api.nomad.hcl`, template DB+Redis env |
| **M3** | *Load-aware WhisperLive prototype (Compose)* — bot connects to least-busy WL | WL publishes `sessions` → Redis sorted-set; **Vexa-Bot implements Redis ZRANGE/ZREM selection & auto-retry**; validate with `docker-compose up` |
| **M4** | *Vexa-Bot (manual Nomad)* — `nomad dispatch` joins Google Meet using Redis-chosen WL | parameterised job, confirm bot's Redis lookup works in Nomad env |
| **M5** | *Bot-Manager on Nomad* — `POST /bots` launches bot & joins meeting | `jobs/bot-manager.nomad.hcl`, lifecycle helpers (no WL selection logic needed) |
| **M6** | *WhisperLive (Nomad)* — WL instances publish load metric; bot audio flows | `jobs/whisperlive-(gpu|cpu).nomad.hcl`, verify Redis TTL heartbeat |
| **M7** | *Transcription Collector* — segments consumed & persisted | `jobs/transcription-collector.nomad.hcl`, Redis stream env |
| **M8** | *API Gateway online* — upstream routes to internal services | `jobs/api-gateway.nomad.hcl`, Traefik or native LB |
| **M9** | *Local autoscaling demo* — Nomad Autoscaler scales WhisperLive-GPU & WL-CPU based on Redis session metric | autoscaler config, synthetic load |
| **M10** | *Cloud foundation (CPU-only)* on GCP | Terraform VPC, Nomad servers, Cloud SQL, Artifact Registry |
| **M11** | *Attach on-prem GPU client* | Join bare-metal client, GPU jobs schedulable |
| **M12** | *GPU fallback to GCP* | autoscaling policy invokes pre-emptible GPU pool |

---

## 5 • Technical Standards & Conventions
• **Service Discovery provider** — start with `provider = "nomad"` (built-in catalog, zero DNS).  Switch to `provider = "consul"` **after M8** if we need Consul DNS or Connect service-mesh.
• **Networking** — `network { mode = "bridge" }`; dynamic ports.
• **Service Discovery Template**
```hcl
{{ with nomadService "redis" }}
{{- $svc := index . 0 -}}
REDIS_URL="redis://{{ $svc.Address }}:{{ $svc.Port }}/0"
{{ end }}
```
• **WhisperLive load metric** — every WL instance publishes its current `sessions` count to `wl:<AllocID>:sessions` (TTL 30 s) *and updates score in `wl:rank` sorted-set*; **bots** pick the lowest-score member via `ZRANGE` (see docs).  Bot removes bad URL with `ZREM` on failure.
• **Dispatch meta** — `WHISPER_LIVE_URL` no longer passed; bots discover at runtime. (Still allowed for forced overrides.)
• **Image Tagging** — development: `services/<name>:dev`; production: semver tags in Artifact Registry.
• **Secrets** — distributed via Nomad/Vault template blocks; never baked into images.
• **Observability** — each job defines a health-check; cluster metrics shipped to Cloud Monitoring in prod.

## 5.1 • WhisperLive: Load-Aware Routing & Autoscaling

### 5.1.1  Runtime metric (authoritative source of truth)
```
Redis key pattern :  wl:<NomadAllocID>:sessions    =>  Integer (current active audio sessions)
TTL                :  30 seconds  (key expires if the allocation dies or process hangs)
Update cadence     :  on every session_start  (++1) and session_end (--1)
                     defensive guard: publish heartbeat every 15 s even if count unchanged.
```
*Implementation stub in `whisper_live/server.py` (added under `TranscriptionServer`):*
```python
import redis, os, time, threading, uuid
alloc_id = os.getenv("NOMAD_ALLOC_ID", str(uuid.uuid4())[:8])
REDIS = redis.from_url(os.environ.get("REDIS_STREAM_URL", "redis://localhost:6379/0"))

def publish_sessions(count: int):
    REDIS.setex(f"wl:{alloc_id}:sessions", 30, count)
```

### 5.1.2  Bot-Manager selection algorithm *(pseudo-code)*
```
services = consul.catalog("whisperlive-gpu")          # healthy allocations
candidates = []
for s in services:
    load = redis.get(f"wl:{s.ID}:sessions") or 999
    candidates.append((load, s))
load, chosen = min(candidates, key=lambda t: t[0])
whisper_url = f"ws://{chosen.Address}:{chosen.Port}/ws"
meta["whisper_url"] = whisper_url                         # inject into Nomad dispatch
```

Edge-cases:
1. **No metric found** → treat as load=999 so hot instances are deprioritised but not blocked.
2. **Metric ≥ hard-limit (e.g. 10)** → Bot-Manager can refuse dispatch with HTTP 503; Autoscaler (below) should have already reacted.
3. **Bot fails to connect** (socket error) → Bot exits with non-zero; Bot-Manager re-reads catalog and retries once with next candidate.

### 5.1.3  Nomad Autoscaler policy (local dev version)
*File:* `autoscaler/whisperlive.hcl`
```hcl
policy "wl-gpu-by-sessions" {
  job       = "whisperlive-gpu"
  min       = 1
  max       = 6

  target "custom" {
    source       = "redis"
    address      = "redis.service.consul:6379"
    key_pattern  = "wl:*:sessions"
    statistic    = "average"            # average sessions across allocs
  }

  strategy "target-value" {
    target = 6                           # aim for ≤-6 sessions per GPU
  }
}
```

*CPU variant* mirrors the same policy but with a lower target (e.g. 2).

### 5.1.4  Future hardening (beyond MVP)
1. **GPU utilisation metric** — scrape NVML and expose to Prometheus, replace the Redis metric in the Autoscaler.
2. **Weighted Service Mesh** — once Consul Connect is enabled, store the session count as `weight` metadata; Envoy will load-balance automatically without Bot-Manager logic.

---

## 6 • Lessons Carried Forward
1. *Quote hell in templates* — avoid hand-crafted JSON; build a map → `printf` → `toJSON` *(escaped but human-readable)*.
2. *CNI prerequisites* — install reference plugins before any `mode = "bridge"` workloads.
3. *Image pull behaviour* — `force_pull = true` forces remote pulls; omit for local images.
4. *API reachability* — expose Nomad API on **0.0.0.0** so bridge-networked tasks can dispatch jobs.
5. *Discovery vs Mesh* — Consul catalog is enough for early phases; Connect side-cars (mTLS, intentions) will be piloted after M9.

---

## 8 • Key Architectural Decisions
| Code | Decision |
|------|----------|
| **KAD-A** | WhisperLive publishes `sessions` metric + heartbeat to Redis and updates `wl:rank` sorted-set. |
| **KAD-B** | **Vexa-Bot** selects the best WL at each (re)connect using Redis `ZRANGE`/`ZREM`; self-heals on failures. |
| **KAD-C** | Nomad Autoscaler reads the same Redis metrics for GPU scaling; avoids Prometheus dependency in dev. |
| **KAD-D** | Consul Connect adoption deferred until baseline stable; will start in permissive mTLS mode with Admin-API. |

---

*This file supersedes historical `planstate.md` for day-to-day planning while preserving key lessons. (Last updated: 2025-06-21)* 
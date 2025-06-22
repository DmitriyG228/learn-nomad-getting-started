# WhisperLive – Session-Aware Routing & Autoscaling

This document captures the **single-Redis-sorted-set** pattern we use to route Vexa-Bots to the least-loaded WhisperLive instance and to drive autoscaling.

---

## 1  Runtime data model

| Redis Key | Type | Purpose | TTL |
|-----------|------|---------|-----|
| `wl:rank` | *sorted-set* | Member = **WebSocket URL** (`ws://IP:port/ws`)  Score = _current session count_ | none (scores updated in-place) |
| `wl:hb:<ws_url>` | string | Heart-beat flag that proves the instance is alive | 35 s |

### Publishing logic (inside WhisperLive)
```python
alloc_id = os.getenv("NOMAD_ALLOC_ID", "local")
ws_url   = f"ws://{pod_ip}:{listen_port}/ws"

def publish(count: int):
    pipe = redis.pipeline()
    pipe.zadd("wl:rank", {ws_url: count})          # update score
    pipe.setex(f"wl:hb:{ws_url}", 35, 1)           # keep-alive flag
    pipe.execute()
```
*Call `publish()` on every* **session_start**, **session_end**, *and from a 15-second heartbeat timer.*

---

## 2  Bot-side selection algorithm

**Goal:** always connect to the lowest-load, still-alive WL; retry quickly if it fails.

```ts
async function nextWsCandidate(offset=0): Promise<string|null> {
  const urls = await redis.zRange("wl:rank", offset, offset);
  return urls[0] ?? null;            // lowest score ➜ index 0,1,…
}

async function connect(offset=0) {
  const url = await nextWsCandidate(offset);
  if (!url) {                       // no capacity – wait & retry from head
    setTimeout(() => connect(0), baseDelay);
    return;
  }

  const ws = new WebSocket(url);

  ws.onopen  = () => { /* success path */ };

  ws.onerror = ws.onclose = async () => {
    await redis.zRem("wl:rank", url);         // drop bad candidate
    connect(offset + 1);                      // try next best
  };
}
```

Properties:
* **Self-healing** – the first bot that hits a dead URL removes it.
* **Fairness** – scores update immediately, so heavily loaded nodes drift deeper in the set.
* **No extra services** – only core Redis commands; no Lua or HTTP helpers.

---

## 3  Autoscaling policy (Nomad Autoscaler)

The same `wl:*:sessions` keys feed scaling decisions.

```hcl
policy "wl-gpu-by-sessions" {
  job = "whisperlive-gpu"
  min = 1
  max = 6

  target "custom" {
    source      = "redis"
    address     = "redis.service.consul:6379"
    key_pattern = "wl:*:sessions"   # average sessions/*
    statistic   = "average"
  }

  strategy "target-value" { target = 6 }
}
```

If average sessions > 6, Autoscaler adds a GPU allocation; idle clusters (<2) scale down.

---

## 4  Failure scenarios & behaviour

| Failure | Effect | Recovery path |
|---------|--------|---------------|
| WhisperLive crash | Heart-beat key expires → bots remove URL → Autoscaler replaces instance | automatic |
| Bot-Manager outage | Bots read directly from Redis, no dependency | none needed |
| Redis outage | Bots fall back to previous URL; reconnect fails until Redis returns | investigate Redis HA |

---

## 5  Roll-back & future work

*Replace strategy later with Consul Connect weighted service-mesh.*  The sorted-set remains a useful metric source for the Autoscaler even after Envoy handles runtime LB.

---

*Last updated by planstate sync — 2025-06-22* 
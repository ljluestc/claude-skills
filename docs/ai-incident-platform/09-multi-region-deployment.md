# 09 — Multi-Region Deployment

## Strategy: Active/Active Across Clouds

The platform runs **active/active** in at least two regions on each of EKS, GKE, and AKS. Anycast DNS + global load balancer steer users to the nearest healthy region. Stateful components replicate asynchronously across regions and (where required) across clouds.

```
                   ┌──────────────── Global Anycast Edge ────────────────┐
                   │  WAF · DDoS · TLS termination · geo-routing          │
                   └───┬─────────────────┬──────────────────┬─────────────┘
                       │                 │                  │
        ┌──────────────▼──┐  ┌───────────▼──┐  ┌────────────▼───────┐
        │ EKS  us-east-1  │  │ GKE eu-west1 │  │ AKS  eastasia      │
        │ EKS  us-west-2  │  │ GKE asia-ne1 │  │ AKS  westeurope    │
        └──────────────┬──┘  └───────────┬──┘  └────────────┬───────┘
                       │                 │                  │
                ┌──────▼─────────────────▼──────────────────▼──────┐
                │  Async cross-region replication (per-store)        │
                │  Qdrant snapshots · OS snapshots · Postgres WAL    │
                │  Kafka MirrorMaker · WORM object replication       │
                └────────────────────────────────────────────────────┘
```

## Region Topology

Each region is a self-contained "cell" with:

- 1 Kubernetes cluster (EKS / GKE / AKS).
- Service mesh (Istio or Linkerd) with mTLS, retry budgets, locality-aware load balancing.
- Local Kafka cluster (RF=3, rack-aware).
- Local OpenSearch + Qdrant + Postgres + Redis.
- Local WORM bucket replicated bidirectionally to peer-cloud bucket.
- Local OTel Collector → regional Mimir/Loki/Tempo, then federated to a global Grafana.

Regions are independent: a region can serve traffic with no cross-region calls in the synchronous path.

## Routing

- **Anycast DNS** (Cloudflare/Front Door) returns the nearest healthy region.
- **Health checks** at the region edge probe `/v1/healthz` (composite: gateway, retrieval, orchestrator, OPA, OTel pipeline).
- **Failover policy:** if a region's composite health is `unhealthy` for `> 60s`, anycast withdraws the prefix; clients are reattracted within `< 30s` (TTL + BGP).
- **Sticky failover:** sticky session cookies are scoped per region; anycast failover reissues the cookie on first request to the new region.

## Data Replication

| Store | Replication mode | RPO target | Notes |
|---|---|---|---|
| Postgres metadata | Async logical replication; one writer pinned per tenant by consistent hash; replicas elsewhere. | `≤ 1 min` | Reads from local replica with bounded-staleness header. |
| Qdrant vector DB | Periodic snapshots (every 15m) shipped to peer region; full restore on promotion. | `≤ 15 min` | Live writes use the local cluster; embeddings re-derivable from object store. |
| OpenSearch | ILM snapshots to object store every 5m; cross-region restore on promotion. | `≤ 5 min` | Hot tier replicated; warm/cold from snapshot. |
| Kafka | MirrorMaker 2 mirrors `events.*` and `embeddings.*` topics across regions for DR; primary path remains regional. | `0` (locally durable) | DR mode replays from peer cluster. |
| Object store (events, models, audit) | Bi-directional cross-region/cross-cloud replication with object lock + versioning. | `0–60 s` | Used as the canonical replay source. |
| Audit log (WORM) | Synchronous double-write to local + peer-cloud bucket. | `0` | Compliance requirement. |
| Redis cache | Not replicated. | n/a | Caches are warmed in the failover region within minutes. |

## Single-Writer per Tenant (Metadata)

Metadata writes for a given `tenant_id` go to one region at a time, chosen by consistent hash. This avoids split-brain in `runs` and `audit_events` during partitions.

- The region map is held in a control-plane CRD synced via Argo CD.
- A planned writer migration uses a two-phase handoff: drain writes in the old region, fence with a Postgres advisory lock, replay any tail through MirrorMaker, then unfence in the new region.
- Unplanned failover uses fencing tokens: writes from the old region with a stale token are rejected if connectivity returns.

## Multi-Cloud Considerations

- **Crossplane** (or Terraform) provisions equivalent infrastructure in each cloud from a single declarative manifest set.
- **Argo CD ApplicationSets** reconcile the same Helm/Kustomize artifacts to all clusters; cloud-specific values are overlays.
- **Argo Rollouts** drive progressive delivery (5% → 25% → 100%) gated by per-cloud SLO burn-rate metrics; if EKS burns budget on a release, GKE and AKS halt automatically.
- **Egress cost control:** cross-cloud replication traffic is metered and capped; non-essential replication (e.g., Redis cache) is disabled.
- **Identity:** a single OIDC IdP federated across clouds; SPIFFE/SPIRE issues workload identities consistently.
- **Networking:** dedicated interconnects (Direct Connect / Cloud Interconnect / ExpressRoute) for replication traffic between clouds; failover to public TLS-encrypted paths if a private link is down.

## Locality and Sovereignty

- Tenants can pin to specific regions/clouds to satisfy data-residency requirements (synthetic illustrative config: `region_pin: ["eu-west1", "westeurope"]`).
- The retrieval and storage layers refuse cross-region reads when the tenant is pinned and the request hits the wrong region; the gateway returns a `308` redirect to the correct region.

## Deploy Pipeline

1. PR merged to `main` builds OCI artifacts signed with cosign.
2. Argo CD sync triggers a canary in one EKS region (smallest blast radius).
3. Argo Rollouts evaluates SLO burn-rate, error rate, and citation faithfulness for `30m`.
4. If healthy, rollout proceeds to remaining EKS regions, then GKE, then AKS, with the same gates.
5. Any cloud halting halts the global rollout.
6. Rollback is a single Argo command; takes effect inside a region within 90s.

## DR Drills

- **Quarterly** full-region kill: take down EKS us-east-1; verify anycast withdrawal, failover to us-west-2 / GKE eu-west1, and read promotion of replicas. Measure observed RTO vs target.
- **Monthly** cloud-failover canary for a small tenant cohort: actively force traffic to a non-primary cloud.
- **Weekly** chaos: random AZ kill in one region; expect no SLO breach.

## What This Buys / Costs

Buys: regional failure tolerance, cloud failure tolerance, regulated tenant isolation, deploy independence per cloud.

Costs: replication egress, infra duplication, operational complexity (three control planes), latency penalty on rare cross-region operations. See [10 — architecture-decisions](10-architecture-decisions.md) for the explicit tradeoff record.

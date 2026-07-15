# Change: Fix cart probes after managed Valkey cutover (TLS + AUTH)

## Summary

Production cart pods failed readiness and liveness on `:8080` (`connection refused` /
gRPC connect timeout) after pointing `VALKEY_ADDR` at ElastiCache. Managed Valkey
requires transit encryption and an AUTH token; the chart only set the address.
The process hung in Redis connect retries during startup and never bound the
gRPC port. This change wires `VALKEY_TLS`, `VALKEY_TLS_HOST`, and
`VALKEY_PASSWORD` (via ESO from the Terraform-managed ASM secret) and documents
the operator deploy order.

## Context

* Directive #3 moved production cart state from in-cluster `valkey-cart` to
  Multi-AZ ElastiCache Valkey (`transit_encryption_enabled`, `auth_token`).
* Chart `values-prod.yaml` set `VALKEY_ADDR=valkey-cart.techx.internal:6379` and
  an `nc` init gate only. Init succeeds on TCP; the app still cannot speak the
  Redis protocol without TLS + password.
* Live symptom on pod IP `10.0.34.115`: liveness `dial tcp …:8080: connection
  refused`, readiness `failed to connect … within 3s`, container restarts.

## Before

* Cart env: `VALKEY_ADDR` only (no `VALKEY_TLS` / `VALKEY_PASSWORD` /
  `VALKEY_TLS_HOST`).
* No ExternalSecret for `techx-prod-tf2/valkey-cart`.
* StackExchange.Redis `ConnectRetry=30` blocked DI/`Initialize()` before
  Kestrel bound `:8080` → probe failures and restarts.
* NetworkPolicy (when enabled) only allowed egress to the in-cluster
  `valkey-cart` pod, not VPC ElastiCache addresses.

## After

* Production cart sets `VALKEY_TLS=true`, `VALKEY_TLS_HOST` to the ElastiCache
  primary endpoint hostname (certificate SAN), and `VALKEY_PASSWORD` from
  Secret `techx-corp-valkey-cart`.
* `secrets-chart` can sync ASM `techx-prod-tf2/valkey-cart` property
  `password` → K8s key `VALKEY_PASSWORD`.
* Cart NetworkPolicy egress also allows TCP `6379` to `10.0.0.0/8` for managed
  Valkey when NetworkPolicy enforcement is turned on later.

## Technical Design Decisions

* Keep stable private DNS in `VALKEY_ADDR`; set `VALKEY_TLS_HOST` to the AWS
  primary endpoint so TLS hostname verification matches the ElastiCache cert
  without putting the AWS endpoint in the connection address.
* Reuse the existing cart env vars already implemented in the platform image
  (`VALKEY_TLS`, `VALKEY_PASSWORD`, `VALKEY_TLS_HOST`) — no image rebuild.
* ExternalSecret is prod-gated (`valkeyCart.enabled`) so dev continues with
  unauthenticated in-cluster Valkey.
* Alternatives rejected: plaintext password in Helm values; disabling ElastiCache
  AUTH/TLS; connecting only via the AWS endpoint (loses the private-DNS
  stability goal of Directive #3).

## Implementation Details

1. Add optional `valkeyCart` block to `secrets-chart` values and an
   ExternalSecret mapping ASM JSON `password` → `VALKEY_PASSWORD`.
2. Enable the secret in `secrets-chart/values-prod.yaml` with remote key
   `techx-prod-tf2/valkey-cart`.
3. Extend `components.cart.envOverrides` in `values-prod.yaml` with TLS + AUTH.
4. Allow cart NetworkPolicy egress to `10.0.0.0/8:6379`.
5. Bump app chart to `0.48.1` and secrets chart to `0.1.1`.

## Files Changed

**Application chart:**
* `values-prod.yaml` — Cart managed Valkey TLS, TLS host, password secretKeyRef.
* `templates/networkpolicy.yaml` — Cart egress to VPC private range for Valkey.
* `Chart.yaml` — Version `0.48.1`.

**Secrets chart:**
* `secrets-chart/values.yaml` — `targets.valkeyCart` and `valkeyCart` defaults.
* `secrets-chart/values-prod.yaml` — Enable managed Valkey remote key.
* `secrets-chart/templates/externalsecrets.yaml` — ExternalSecret for Valkey AUTH.
* `secrets-chart/Chart.yaml` — Version `0.1.1`.

**Documentation:**
* `docs/changes/2026-07-15-fix-cart-managed-valkey-tls-auth.md` — This change record.

## Dependencies and Cross-Repository Impact

* Depends on infra already applied: `module.commerce_ha` ElastiCache replication
  group with AUTH secret ARN granted to ESO
  (`external_secrets` secret_arns includes `valkey_auth_secret_arn`).
* Platform cart image already reads `VALKEY_TLS` / `VALKEY_PASSWORD` /
  `VALKEY_TLS_HOST` — no platform change required.
* Related: `techx-corp-infra/docs/changes/2026-07-14-directive-03-commerce-stateful-ha.md`

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Cart can complete Redis connect and bind gRPC `:8080`; cart API works against managed Valkey |
| **Infrastructure** | No Terraform change; uses existing ASM secret and ElastiCache |
| **Deployment** | Deploy `techx-corp-secrets` first (wait Ready), then app chart / Argo sync |
| **Performance** | Removes multi-minute hang/restart loop during cart startup |
| **Security** | AUTH token stays in ASM → ESO → secretKeyRef; transit TLS required |
| **Reliability** | Restores Ready replicas during managed-Valkey rollout |
| **Cost** | None |
| **Backward compatibility** | Dev unchanged (in-cluster Valkey, secret disabled) |
| **Observability** | Successful connect logs `Successfully connected to Redis` |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Secrets template | `helm template techx-corp-secrets ./secrets-chart -f secrets-chart/values.yaml -f secrets-chart/values-prod.yaml` | Pending deploy validation |
| App lint | `helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | Pending deploy validation |

### Manual Verification

```cmd
cd /d techx-corp-chart
helm upgrade --install techx-corp-secrets .\secrets-chart -n techx-corp-prod ^
  -f secrets-chart\values.yaml -f secrets-chart\values-prod.yaml
kubectl get externalsecret,secret -n techx-corp-prod | findstr valkey
kubectl wait --for=condition=Ready externalsecret/techx-corp-valkey-cart -n techx-corp-prod --timeout=120s
```

Then sync / upgrade the app chart and:

```cmd
kubectl get pods -n techx-corp-prod -l opentelemetry.io/name=cart -o wide
kubectl logs -n techx-corp-prod -l opentelemetry.io/name=cart -c cart --tail=50
```

Expect: Ready `1/1`, log line `Successfully connected to Redis`, no sustained
connection refused on `:8080`.

### Remaining Verification (Post-Merge)

* Argo CD prod Application Synced/Healthy after merge.
* Cart success rate on storefront / k6 browse→cart path.
* If replication group is recreated, refresh `VALKEY_TLS_HOST` from
  `terraform output -raw commerce_valkey_primary_endpoint`.

## Migration or Deployment Notes

1. Confirm ASM secret `techx-prod-tf2/valkey-cart` exists (Terraform commerce_ha).
2. Deploy secrets chart and wait for ExternalSecret Ready.
3. Deploy app chart overlay (`values-prod.yaml`) or Argo sync.
4. Confirm new cart pods receive `VALKEY_TLS`, `VALKEY_TLS_HOST`, and
   `VALKEY_PASSWORD` (secretKeyRef) before deleting any remaining
   in-cluster valkey PVC.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| `VALKEY_TLS_HOST` wrong after RG recreate | Low | High | Update host from terraform output; redeploy cart |
| ExternalSecret not Ready (IAM/key) | Low | High | Check ESO IRSA includes valkey secret ARN; fix then re-sync |
| Temporary cart downtime during rollout | Medium | Medium | Keep one Ready replica during rollout; PDB minAvailable 1 |

**Rollback procedure:**

1. Revert `values-prod.yaml` cart `envOverrides` / re-enable in-cluster
   `valkey-cart` if required (cart session data on managed Valkey is not
   automatically migrated back).
2. Or remove TLS/password env overrides only if rolling back ElastiCache itself.

<!-- Change trail: @hungxqt - 2026-07-15 - Document cart managed Valkey TLS+AUTH probe fix. -->

# Change: Point Mem0 master ExternalSecret at Mem0 RDS secret

## Summary

The Mem0 migrate Job failed with `password authentication failed for user "postgres_admin"` because `secrets-chart` `mem0.masterRemoteKey` pointed at the **commerce** RDS managed master secret (`techx-prod-tf2-postgresql`), not the **Mem0** RDS secret (`techx-prod-tf2-mem0-postgres`, master user `mem0_admin`). The remote key is updated to the correct Mem0 RDS-managed secret name.

## Context

Job error after host/env wiring:

```text
psycopg.OperationalError: connection failed: connection to server at "10.0.10.66", port 5432 failed:
FATAL: password authentication failed for user "postgres_admin"
```

Live AWS (us-east-1) comparison:

| Instance | Master user | Managed secret name |
|---|---|---|
| `techx-prod-tf2-postgresql` (commerce) | `postgres_admin` | `rds!db-012e983a-9341-49cf-8a12-5928f016905d` |
| `techx-prod-tf2-mem0-postgres` (Mem0) | `mem0_admin` | `rds!db-380876ae-6adf-417d-8234-395538d8a904` |

Chart host `mem0.rds.host` correctly targets Mem0; only the master credential source was wrong. ESO had synced the wrong secret successfully (`SecretSynced`), so the Job used commerce username/password against Mem0 RDS.

## Before

* `secrets-chart/values-prod.yaml` → `mem0.masterRemoteKey: rds!db-012e983a-9341-49cf-8a12-5928f016905d`
* K8s secret `techx-corp-mem0-rds-master` contained `MEM0_RDS_MASTER_USERNAME=postgres_admin` (commerce)

## After

* `masterRemoteKey: rds!db-380876ae-6adf-417d-8234-395538d8a904` (Mem0 RDS managed secret)
* After ESO refresh, K8s secret username is expected to be `mem0_admin` (password from that secret only; never commit values)

## Technical Design Decisions

* **Chosen:** fix values pin to the current Mem0 managed secret name (same pattern as before).
* **Rejected:** read host/user from ASM JSON — Mem0 managed secret currently exposes only `username`/`password`; host stays in app chart values.
* **Note:** After any Mem0 RDS recreate, secret name/ARN changes; re-run `terraform output mem0_postgresql_master_user_secret_arn` and update this pin; ensure ESO IRSA still lists the new ARN (`module.mem0_postgresql.master_user_secret_arn` in production `external_secrets.secret_arns`).

## Implementation Details

1. Confirmed RDS instances and master secret ARNs in `us-east-1` (account `493499579600`).
2. Updated prod secrets overlay `masterRemoteKey` to Mem0 secret name.
3. Documented the commerce-vs-Mem0 mix-up so it is not reintroduced.

## Files Changed

**Secrets chart configuration:**
* `secrets-chart/values-prod.yaml` — Correct Mem0 `masterRemoteKey`.

**Documentation:**
* `docs/changes/2026-07-19-mem0-master-secret-wrong-rds.md` — This change record.

## Dependencies and Cross-Repository Impact

* **techx-corp-infra:** No code change. ESO role already includes `module.mem0_postgresql.master_user_secret_arn`. If AccessDenied appears after the key change, re-apply production Terraform so the policy matches the live secret ARN.
* **techx-corp-platform / app chart:** No change required for this credential source fix (host env wiring is separate).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Migrate bootstrap authenticates as `mem0_admin` against Mem0 RDS |
| **Infrastructure** | No TF change |
| **Deployment** | secrets Application sync → ESO refresh → recreate/retry migrate Job |
| **Security** | Stops using commerce master credentials against Mem0; least privilege restored |
| **Reliability** | Unblocks password auth failure on migrate |
| **Backward compatibility** | Prod-only overlay; no shared default change |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Live RDS inventory | `aws rds describe-db-instances --region us-east-1` | Mem0 master `mem0_admin`; commerce `postgres_admin` |
| Live secret mapping | ASM describe + username-only parse | Wrong pin = commerce; correct pin = `mem0_admin` |
| ESO status (before fix) | `kubectl get externalsecret techx-corp-mem0-rds-master` | SecretSynced with wrong payload |

### Manual Verification

* K8s secret username was `postgres_admin` while connecting to Mem0 endpoint — confirms cross-wiring.
* Did not print or log password material.

### Remaining Verification (Post-Merge)

1. Sync `techx-corp-secrets` Application (or wait for Argo).
2. Confirm ExternalSecret Ready; K8s username becomes `mem0_admin` (decode username key only).
3. Retry migrate Job (Force/Replace or new tag suffix).
4. Bootstrap + `alembic upgrade head` succeed.

```cmd
REM username only — do not print password
kubectl -n techx-corp-prod get secret techx-corp-mem0-rds-master -o jsonpath="{.data.MEM0_RDS_MASTER_USERNAME}"
```

```powershell
# PowerShell: decode username only
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
  (kubectl -n techx-corp-prod get secret techx-corp-mem0-rds-master -o jsonpath="{.data.MEM0_RDS_MASTER_USERNAME}")
))
```

## Migration or Deployment Notes

1. Merge/push chart change (GitOps).
2. Wait for secrets-chart sync and ExternalSecret refresh (interval may be up to 1h unless forced re-sync/annotation).
3. To force ESO reconcile sooner (if operators use it): annotate ExternalSecret or re-sync Argo app — prefer Argo over ad-hoc kubectl when auto-sync is on.
4. Re-run migrate Job after secret content updates.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| ESO AccessDenied on new ARN | Low | High | Terraform already grants Mem0 master secret; re-apply if drifted |
| Stale K8s secret until refresh | Medium | Medium | Re-sync secrets app; wait refreshInterval or force reconcile |
| Future RDS recreate changes secret id | Medium | High | Update pin from terraform output; document in values comments |

**Rollback procedure:**

1. Revert `masterRemoteKey` only if intentional rollback to previous (broken) pin — not recommended.
2. Prefer keep Mem0 secret pin; fix other issues separately.

<!-- Change trail: @hungxqt - 2026-07-19 - Document Mem0 master secret pinned to wrong commerce RDS secret. -->

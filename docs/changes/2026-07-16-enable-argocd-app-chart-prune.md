# Change: Enable Argo CD automated prune on app chart Applications

## Summary

Production Application `techx-corp` now uses `syncPolicy.automated.prune: true`
(matching development `techx-corp-dev`). Objects no longer rendered by the app
chart—such as in-cluster `kafka` / `valkey-cart` after MSK/ElastiCache cutover—
are deleted automatically on sync. Secrets Applications and root app-of-apps
remain **`prune: false`**.

## Context

* Prod `Service/kafka` and `StatefulSet/kafka` stayed OutOfSync after
  `components.kafka.enabled: false` because prune was off.
* Dev app chart already had `prune: true`; prod lagged at `prune: false`.
* Secrets chart docs explicitly forbid secrets `prune: true` (risk of deleting
  live credential Secrets / ExternalSecrets). Root app-of-apps keeps prune off
  to avoid cascade-deleting child Application CRs.

## Before

```yaml
# gitops/clusters/prod/application.yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

* Dev app chart: already `prune: true`.
* Secrets + root: `prune: false`.

## After

```yaml
# gitops/clusters/prod/application.yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

* Dev header comment aligned (policy unchanged: already prune true).
* Ops docs: app chart prune true; secrets/root stay false; kafka orphan section
  updated for auto-prune path.

## Technical Design Decisions

* **Enable prune only on app chart Applications** — high value for component
  disable (MSK/ElastiCache), lower risk than secrets prune.
* **Keep secrets `prune: false`** — ExternalSecret deletion or Secret pruning
  can break ESO-managed credentials; see `docs/operations/external-secrets.md`.
* **Keep root `prune: false`** — accidental removal of Application CRs from
  `gitops/clusters/*` must not cascade-delete workloads without explicit ops.
* **No `PrunePropagationPolicy` change** — default background delete is fine;
  StatefulSet PVC retention remains Retain (PVCs may need optional manual reclaim).

## Implementation Details

1. Set `spec.syncPolicy.automated.prune: true` on
   `gitops/clusters/prod/application.yaml`.
2. Correct stale “prune OFF” header on dev Application (policy already true).
3. Update `gitops/README.md` and `docs/operations/gitops-argocd.md` policy text
   and MSK/valkey orphan cleanup guidance.

## Files Changed

**GitOps Applications:**

* `gitops/clusters/prod/application.yaml` — `prune: true` on automated sync.
* `gitops/clusters/dev/application.yaml` — header comment only (already prune true).

**Documentation:**

* `gitops/README.md` — default child sync policy table.
* `docs/operations/gitops-argocd.md` — auto-sync defaults; orphan cleanup notes.
* `docs/changes/2026-07-16-enable-argocd-app-chart-prune.md` — This change record.

## Dependencies and Cross-Repository Impact

None. Cluster effect is via Argo reconciling the Application CR after this Git
path is applied (root app-of-apps or direct apply of the Application manifest).

Related prior work: MSK cutover in `values-prod.yaml`; kafka orphan analysis in
`docs/changes/2026-07-16-fix-statefulset-argocd-drift.md`.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No code change; cluster deletes resources removed from app chart render |
| **Deployment** | After Application CR updates, auto-sync may prune kafka/valkey-cart Service+STS if still disabled |
| **Reliability** | Removing a component from Git deletes it in prod without manual kubectl |
| **Security** | Secrets apps unchanged (`prune: false`) |
| **Backward compatibility** | Operators who relied on prune-off leftovers must use Git re-add or restore |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Manifest review | Inspect `prune: true` under prod Application automated | ✅ Applied |
| Secrets apps | Confirm secrets Application still `prune: false` | ✅ Unchanged |

### Manual Verification

* Compared dev (`prune: true`) and prod (was `false`) Application specs.
* Confirmed secrets Application files not modified.

### Remaining Verification (Post-Merge)

1. After Git merge, ensure Application CR updates (root-prod sync or apply path).
2. `argocd app get techx-corp` — automated prune enabled.
3. `argocd app diff techx-corp` — expect prune of leftover kafka/valkey if present.
4. Wait auto-sync; confirm Service/StatefulSet removed; smoke MSK consumers.
5. Optional: reclaim Retain PVCs if disk should be freed.

## Migration or Deployment Notes

1. Merge this change to the chart repo branch Argo tracks (`main` for prod).
2. Root app-of-apps should update child Application `techx-corp` automatically if
   it manages `gitops/clusters/prod/application.yaml`.
3. Review prune candidates once:

```cmd
argocd app diff techx-corp
argocd app get techx-corp
```

4. Do **not** set `prune: true` on `techx-corp-secrets` / `techx-corp-secrets-dev`
   as part of this change.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Unexpected prune of a still-needed object removed from Git by mistake | Medium | High | Path protection + PR review; `argocd app diff` before merge |
| Prune deletes in-cluster kafka while a consumer still uses `kafka:9092` | Low if MSK cutover done | High | Confirm `KAFKA_ADDR` MSK secret before relying on prune |
| PVC left behind after STS prune | Medium | Low | Optional manual PVC delete; AppProject ignore already lists PVC names |

**Rollback procedure:**

```yaml
# gitops/clusters/prod/application.yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

Revert this commit (or set prune false) and merge. Already-pruned objects are
not recreated unless re-added to the chart render.

<!-- Change trail: @hungxqt - 2026-07-16 - Enable automated prune on production techx-corp Application. -->

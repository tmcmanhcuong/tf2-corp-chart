# Change: Enable Argo CD automated prune on app chart Applications

## Summary

Production Application `techx-corp` now uses `syncPolicy.automated.prune: true`
(matching development `techx-corp-dev`). Objects no longer rendered by the app
chart—such as leftover in-cluster `kafka` / `valkey-cart` after MSK/ElastiCache
cutover—are deleted automatically on sync. Secrets Applications and root
app-of-apps remain **`prune: false`**.

## Context

* Prod leftovers (e.g. disabled components) stayed OutOfSync while prune was off.
* Dev app chart already had `prune: true`; prod lagged at `prune: false`.
* Secrets chart must not prune automatically (credential / ExternalSecret risk).
* Root app-of-apps keeps prune off to avoid cascade-deleting Application CRs.

## Before

```yaml
# gitops/clusters/prod/application.yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

## After

```yaml
# gitops/clusters/prod/application.yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

* Dev header comment aligned (policy already prune true).
* Ops docs updated for app-chart prune vs secrets/root.

## Technical Design Decisions

* Enable prune only on **app chart** Applications.
* Keep secrets and root at `prune: false`.
* No change to ServerSideApply (still off).

## Implementation Details

1. Set `prune: true` on `gitops/clusters/prod/application.yaml`.
2. Align dev Application header comment.
3. Update `gitops/README.md` and `docs/operations/gitops-argocd.md`.

## Files Changed

**GitOps Applications:**

* `gitops/clusters/prod/application.yaml` — `prune: true`.
* `gitops/clusters/dev/application.yaml` — header comment only.

**Documentation:**

* `gitops/README.md` — default child sync policy.
* `docs/operations/gitops-argocd.md` — auto-sync defaults.
* `docs/changes/2026-07-16-enable-argocd-app-chart-prune.md` — This change record.

## Dependencies and Cross-Repository Impact

None. After Git merge, root app-of-apps (or apply of the Application CR) must
reconcile Application `techx-corp` so the live Argo policy updates.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Deployment** | Auto-deletes app-chart objects removed from Git render |
| **Reliability** | Component disable (MSK kafka) no longer leaves managed orphans |
| **Security** | Secrets apps unchanged (`prune: false`) |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Manifest | `prune: true` under prod Application automated | ✅ Applied |
| Secrets apps | still `prune: false` | ✅ Unchanged |

### Remaining Verification (Post-Merge)

```cmd
argocd app get techx-corp
argocd app diff techx-corp
argocd app wait techx-corp --sync --health --timeout 600
```

Expect prune of leftovers no longer in the Helm render (e.g. in-cluster kafka).

## Migration or Deployment Notes

1. Merge to the branch Argo tracks (`main` for prod).
2. Review prune candidates: `argocd app diff techx-corp`.
3. Do **not** enable prune on `techx-corp-secrets`.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Unexpected prune after mistaken Git removal | Medium | High | PR review + `argocd app diff` |

**Rollback:** set `prune: false` on prod Application and merge. Already-pruned
objects are not recreated unless re-added to the chart render.

<!-- Change trail: @hungxqt - 2026-07-16 - Enable automated prune on production techx-corp Application. -->

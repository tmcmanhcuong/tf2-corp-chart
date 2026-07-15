# Change: Local flagd File/UI — `local-*` Keys Only

## Summary

Removed all non-`local-*` feature flag definitions from chart `flagd/demo.flagd.json` so flagd-ui (`/feature`) lists only team self-test twins. BTC original keys remain available via the dual-source HTTP provider. Chart version `0.48.3`.

## Context

* Dual-source flagd: local file + BTC HTTP (HTTP last on key clash).
* Apps dual-read original + `local-*` (OR / max). UI writes the file source only.
* Keeping BTC original names in the local file cluttered the UI and invited operators to toggle non-authoritative copies of mentor/chaos keys.

## Before

* `flagd/demo.flagd.json` contained 15 original keys + 15 `local-*` twins (30 flags).
* `/feature` showed both sets; original-key toggles did not control BTC under dual-source.

## After

* Local flag file has **15 flags**, all prefixed `local-`.
* BTC originals come only from central HTTP in prod (or app OpenFeature defaults when offline/Compose).
* Ops comments in `values.yaml`, `values-prod.yaml`, `values-flagd-sync.yaml` document the local-* UI contract.

## Technical Design Decisions

* **Strip originals from local file** rather than UI filtering — single source of truth for what the file provider exposes.
* **Keep platform/chart JSON in sync** — same content as `techx-corp-platform/src/flagd/demo.flagd.json`.
* **No merge-order change** — HTTP still last; no risk of local original keys soft-bypassing BTC.

## Implementation Details

1. Rewrote `flagd/demo.flagd.json` to `local-*` entries only.
2. Updated flagd comments on base/prod/sync values.
3. Bumped chart to `0.48.3`.

## Files Changed

**Flags:**
* `flagd/demo.flagd.json` — Removed non-`local-*` flags (JSON; no comment trail).

**Configuration:**
* `Chart.yaml` — `0.48.2` → `0.48.3`.
* `values.yaml` — Comment: local file is local-* only.
* `values-prod.yaml` — Comment: UI lists local-* only.
* `values-flagd-sync.yaml` — Same.

**Documentation:**
* `docs/changes/2026-07-15-local-flagd-ui-local-prefix-only.md` — This change record.

Change trail exception for `flagd/demo.flagd.json`: JSON does not support comments. Attribution @hungxqt.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-platform/docs/changes/2026-07-15-local-flagd-ui-local-prefix-only.md`.
* Requires platform dual-read images for `local-*` injection to take effect (already shipped).
* Compose without BTC: only `local-*` flags exist; operators must toggle `local-*` names.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Offline/Compose: original keys resolve to OpenFeature defaults unless BTC HTTP is present; `local-*` still injects via dual-read |
| **Deployment** | ConfigMap update; restart flagd pods so init re-copies emptyDir |
| **Security** | UI no longer presents BTC original key names for local edit |
| **Observability** | `/feature` shows 15 team flags only |
| **Backward compatibility** | Operators who toggled original names in UI must switch to `local-*` |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Flag keys | PowerShell parse JSON keys | ✅ 15 keys, all `local-` |
| Platform sync | Compare platform vs chart file | ✅ Equal after copy |

### Manual Verification

* After Argo sync + flagd restart: `/feature` lists only `local-*`.
* BTC chaos still works via HTTP original keys when dual-source is active.

### Remaining Verification (Post-Merge)

1. Argo sync chart `0.48.3`.
2. Restart flagd Deployment so ConfigMap is re-copied into emptyDir.
3. Confirm UI and `kubectl get cm flagd-config -o yaml` contain only `local-*`.

## Migration or Deployment Notes

```cmd
cd /d techx-corp-chart
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
```

After merge: Argo auto-sync, then restart flagd if emptyDir is stale.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Compose-only operators still toggle old names | Medium | Low | Docs; UI no longer shows them |
| emptyDir stale after ConfigMap change | Medium | Low | Restart flagd pods |

**Rollback procedure:** Restore original+local twin JSON from prior commit; Argo sync + flagd restart.

<!-- Change trail: @hungxqt - 2026-07-15 - Local flagd file/UI exposes local-* keys only. -->

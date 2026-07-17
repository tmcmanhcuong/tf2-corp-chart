# Change: Align local-* flagd ConfigMap twins with BTC definitions

## Summary

Chart `flagd/demo.flagd.json` was regenerated so every `local-<name>` twin uses the same variants, values, defaultVariant, and state as the corresponding BTC original flag, with a `(team local)` description and `local-` key prefix only. Chart version **0.48.8**.

## Context

* Dual-source prod flagd: local file (`local-*` only) + BTC HTTP (original keys).
* Team self-test requires local twins to mirror BTC inject semantics (same percentage steps, int multipliers, bool on/off).
* Platform soft-remediation removal (separate change) depends on local inject being a faithful twin of BTC.

## Before

* 15 `local-*` keys present; structure already close to historical twins.
* Chart version 0.48.7.

## After

* 15 `local-*` keys only; variants/defaultVariant copied from BTC originals (no non-local keys in file).
* Chart version 0.48.8.
* Content kept in sync with `techx-corp-platform/src/flagd/demo.flagd.json`.

## Technical Design Decisions

* **local-* only in file** — BTC originals stay on HTTP source; UI lists team flags only.
* **Copy variants from BTC**, not invent new shapes — max/OR dual-read in apps stays type-safe.
* No change to dual-source merge order (HTTP last on original key names).

## Implementation Details

1. Regenerated `flagd/demo.flagd.json` from BTC base definitions with `local-` prefix.
2. Bumped `Chart.yaml` to 0.48.8.

## Files Changed

**Flags:**
* `flagd/demo.flagd.json` — local-* twins aligned to BTC (JSON; no comment trail).

**Configuration:**
* `Chart.yaml` — 0.48.7 → 0.48.8.

**Documentation:**
* `docs/changes/2026-07-17-local-flags-match-btc.md` — This record.

Change trail exception for `flagd/demo.flagd.json`: JSON does not support comments. Attribution @hungxqt.

## Dependencies and Cross-Repository Impact

* Related: `techx-corp-platform/docs/changes/2026-07-17-remove-flag-soft-remediation.md`.
* App dual-read images required for runtime effect of local toggles; this change only updates ConfigMap definitions (defaults off).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No change until UI/Git toggles a local flag; defaults remain off |
| **Deployment** | ConfigMap update; restart flagd if emptyDir is stale |
| **Security** | UI still has no BTC original key names for local edit |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Platform ↔ chart JSON equal | File compare | Pass |
| Variants match BTC historical defs | Python pair compare | Pass (15/15) |

### Manual Verification

* After Argo sync + flagd restart: ConfigMap and `/feature` show 15 `local-*` flags default off.

### Remaining Verification (Post-Merge)

* Operator restart flagd Deployment if live emptyDir still has old UI-edited state.

## Migration or Deployment Notes

```cmd
cd /d techx-corp-chart
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
```

After merge: Argo auto-sync; restart flagd pods so init re-copies ConfigMap into emptyDir.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| emptyDir retains previous UI toggles | Medium | Medium | Restart flagd after sync; turn flags off in UI |
| Variant mismatch with live BTC HTTP | Low | Low | Generated from known BTC twin set; re-compare if BTC adds flags |

**Rollback procedure:** Revert this commit; Argo sync; restart flagd.

<!-- Change trail: @hungxqt - 2026-07-17 - Document local-* flagd ConfigMap alignment to BTC. -->

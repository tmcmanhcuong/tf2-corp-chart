# Change: Re-enable flagd-ui sidecar in production

## Summary

Production flagd again runs the **flagd-ui** sidecar from base `values.yaml`, so operators can toggle **team-only** local flags via `/feature`. Dual-source merge order is unchanged: BTC central HTTP still wins on shared key names.

## Context

* Dual-source work kept `sidecarContainers: []` so prod had no UI.
* Team asked to re-enable UI for local/team flag toggles without giving up BTC authority on chaos/incident keys.
* UI only edits the shared emptyDir file (`demo.flagd.json`); it cannot write the BTC central document.

## Before

* `values-prod.yaml` and `values-flagd-sync.yaml` set `sidecarContainers: []`, clearing the base flagd-ui sidecar.
* Prod flagd pod: flagd container only (plus init).
* Team flags required Git edits to `flagd/demo.flagd.json` and a flagd restart after ConfigMap sync.

## After

* Prod no longer overrides `sidecarContainers`; base flagd-ui sidecar (port 4000, `SECRET_KEY_BASE` from `techx-corp-flagd-ui`) is active again.
* `values-flagd-sync.yaml` likewise does not clear sidecars.
* Dual `--sources` unchanged (file then HTTP; central wins on clash).
* Access path: frontend-proxy `/feature` → `flagd:4000`. Public CloudFront still **blocks** `/feature`; use Client VPN / internal ALB hostname.

## Technical Design Decisions

* **Inherit base sidecar** rather than re-declaring the full sidecar block in prod — avoids drift from base resource/security settings.
* **Do not open `/feature` on CloudFront** — keep SEC-02 admin-path posture; UI is operator-facing only.
* **Central-last merge remains** — UI toggles of BTC-owned keys only change the local file; effective evaluation still follows central when the key exists there.

## Implementation Details

1. Removed `sidecarContainers: []` from `values-prod.yaml`.
2. Removed `sidecarContainers: []` from `values-flagd-sync.yaml`.
3. Updated comments to describe UI scope (team-only vs BTC keys) and access path.
4. Cross-updated dual-source change doc wording that previously said UI stayed off.

## Files Changed

**Configuration:**

* `values-prod.yaml` — Stop clearing flagd-ui; dual sources retained.
* `values-flagd-sync.yaml` — Same; document UI + dual-source contract.

**Documentation:**

* `docs/changes/2026-07-15-reenable-flagd-ui-prod.md` — this change record.
* `docs/changes/2026-07-15-flagd-dual-source-central-and-local.md` — After/decisions aligned with UI re-enable.

## Dependencies and Cross-Repository Impact

* Requires existing ESO/ASM secret `techx-corp-flagd-ui` / `SECRET_KEY_BASE` (SEC-05). No new infra.
* frontend-proxy already sets `FLAGD_UI_HOST` / `FLAGD_UI_PORT` in base values.
* CloudFront path block for `/feature` (infra) unchanged — intentional.

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | Team-only flags can change live via UI. BTC shared keys still follow central HTTP. |
| **Infrastructure** | No change |
| **Deployment** | flagd Deployment gains second container; Service exposes 4000 again |
| **Security** | UI not on public CF; needs VPN/internal. SECRET_KEY_BASE already via ESO |
| **Reliability** | Sidecar failure does not affect flagd readiness (probes on flagd main only) |
| **Observability** | flagd-ui OTEL env restored with sidecar |
| **Backward compatibility** | Restores prior demo UI path under dual-source rules |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm lint (prod) | `helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | Pass |
| Helm template sidecar | `helm template ...` contains `flagd-ui`, port 4000, dual sources | Pass |

### Manual Verification

* After Argo sync: flagd pods `2/2` Ready (flagd + flagd-ui).
* Via VPN/internal: open `/feature` and toggle a **unique** team key; confirm evaluation changes.
* Toggle a known BTC key in UI while central has it ON: effective value should still match central (not local-only OFF).

### Remaining Verification (Post-Merge)

* Operator smoke after Argo sync; confirm `techx-corp-flagd-ui` Secret exists in `techx-corp-prod`.

## Migration or Deployment Notes

1. Merge chart PR; Argo syncs flagd.
2. Confirm Secret: `kubectl get secret techx-corp-flagd-ui -n techx-corp-prod` (read-only metadata check).
3. Open UI: `https://internal.<your-host>/feature/` (or port-forward) on Client VPN — **not** the public storefront CloudFront URL.
4. Prefer unique team flag names; treat BTC key names as read-only for effective state.

```cmd
cd /d techx-corp-chart
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
helm template techx-corp . -n techx-corp-prod ^
  -f values.yaml -f values-public-alb.yaml -f values-prod.yaml ^
  | findstr /i "flagd-ui FLAGD_UI 4000"
```

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Operators think UI controls BTC chaos flags | Medium | Medium | Docs + central-last merge; mentor still owns effective BTC keys |
| Missing SECRET_KEY_BASE crashes sidecar | Low | Medium | ESO already maps flagd-ui; pod may not be 2/2 until secret present |
| Accidental public exposure of /feature | Low | High | CF still blocks /feature; do not remove block without SEC review |

**Rollback procedure:**

1. Restore `sidecarContainers: []` under `components.flagd` in `values-prod.yaml` (and `values-flagd-sync.yaml` if used).
2. Merge; Argo rolls flagd back to single-container.

<!-- Change trail: @hungxqt - 2026-07-15 - Re-enable flagd-ui sidecar in prod for team-only toggles. -->

# Change: Fix StatefulSet empty volumes / serviceName and document MSK kafka orphans

## Summary

Chart templates no longer emit an empty `volumes:` key (which became
`volumes: null` in last-applied and drifted under Argo CD) and set required
StatefulSet `serviceName` to the component name. Operations docs now explain
why prod `Service/kafka` and `StatefulSet/kafka` stay OutOfSync after MSK
cutover with `prune: false`, and how to delete those leftovers safely.

## Context

* Live prod showed `Service/kafka` and `StatefulSet/kafka` OutOfSync under
  Application `techx-corp` in namespace `techx-corp-prod`.
* `values-prod.yaml` sets `components.kafka.enabled: false` because production
  uses Amazon MSK (`KAFKA_ADDR` / `KAFKA_TLS` from secret `techx-corp-msk`).
  Git therefore does **not** render in-cluster kafka; `prune: false` leaves the
  old objects on the cluster with `argocd.argoproj.io/instance=techx-corp`.
* Separately, when kafka (or other VCT-only StatefulSets) **are** rendered, the
  pod template always emitted bare `volumes:` → last-applied `volumes: null`,
  a classic client-side-apply / Argo field drift. Live STS also had
  `serviceName: ''` because the chart never set it.

## Before

**Prod desired vs live**

* Desired (Helm with `values-prod.yaml`): no `kafka` Service/StatefulSet.
* Live: Service + StatefulSet still present (chart label `techx-corp-0.48.6`,
  Argo instance label set), PVC ignore only in AppProject.

**Rendered StatefulSet (when component enabled)**

* Missing `spec.serviceName`.
* Always rendered empty `volumes:` even with only `volumeClaimTemplates`.

## After

* StatefulSets render `serviceName: <component name>` (matches the component
  Service).
* `volumes:` is emitted only when configMaps, emptyDirs, model cache, or
  `additionalVolumes` are present.
* Chart version `0.48.7`.
* `docs/operations/gitops-argocd.md` documents one-time kafka/valkey-cart
  orphan cleanup for prod MSK/ElastiCache cutover.

## Technical Design Decisions

* **Manual orphan delete, not `prune: true`** — same safety model as OpenSearch
  subchart cleanup; keep Application prune off.
* **Do not re-enable in-cluster kafka in prod** to clear OutOfSync — that
  undoes the MSK cutover.
* **serviceName = component name** — matches existing ClusterIP Service naming;
  single-replica advertised listeners already use `PLAINTEXT://kafka:9092`.
* Empty-volumes fix is conditional on presence of volume sources rather than
  always emitting `volumes: []`, so the field is absent when unused (cleaner
  last-applied).

## Implementation Details

1. `_objects.tpl` (deployment/StatefulSet define):
   * For `.stateful`, set `serviceName: {{ .name }}`.
   * Gate the `volumes:` block on
     `mountedConfigMaps | mountedEmptyDirs | additionalVolumes | modelDelivery`.
2. Bump `Chart.yaml` version to `0.48.7` so live labels show the fix revision.
3. Document prod orphan cleanup for kafka and valkey-cart in GitOps ops doc.

## Files Changed

**Templates:**

* `templates/_objects.tpl` — StatefulSet `serviceName`; omit empty `volumes`.

**Chart metadata:**

* `Chart.yaml` — version `0.48.7`.

**Documentation:**

* `docs/operations/gitops-argocd.md` — MSK/ElastiCache leftover cleanup section.
* `docs/changes/2026-07-16-fix-statefulset-argocd-drift.md` — This change record.

## Dependencies and Cross-Repository Impact

None for the template change. Cluster cleanup is operator-side kubectl after
confirming MSK/ElastiCache traffic. Related secret wiring already lives in
`values-prod.yaml` and secrets-chart (`techx-corp-msk`).

## Impact Analysis

| Dimension | Impact |
|---|---|
| **Application behavior** | No intentional runtime change for services that already have volumes; STS gains explicit `serviceName` |
| **Infrastructure** | No Terraform change |
| **Deployment** | Argo sync applies new chart labels; prod OutOfSync for kafka requires **manual delete** of orphans (not auto-prune) |
| **Reliability** | Correct `serviceName` improves StatefulSet network identity semantics |
| **Backward compatibility** | Safe for existing PVCs; serviceName change from `""` to component name is additive |
| **Observability** | Argo should leave OutOfSync for kafka/valkey after orphan delete + next reconcile |

## Validation

### Automated Checks

| Check | Command / Tool | Result |
|---|---|---|
| Helm render (prod) | `helm template techx-corp . -n techx-corp-prod -f values.yaml -f values-public-alb.yaml -f values-prod.yaml` | ✅ No `name: kafka` Service/STS; chart labels `0.48.7` |
| Helm render (base kafka) | Same without prod overlay / kafka enabled | ✅ `serviceName: kafka`; no empty `volumes:` before `volumeClaimTemplates` |

### Manual Verification

* Compared user-provided live kafka manifests with prod values: component
  disabled for MSK; last-applied on STS contained `"volumes":null` and
  `serviceName: ''`.
* Confirmed `values-prod.yaml` MSK env overrides on checkout/accounting/
  fraud-detection.

### Remaining Verification (Post-Merge)

1. Merge chart change; allow Argo sync for remaining rendered resources.
2. Operator deletes orphaned kafka (and valkey-cart if present) per
   `docs/operations/gitops-argocd.md`.
3. `argocd app get techx-corp` — confirm no OutOfSync for those names.
4. Smoke checkout/accounting/fraud-detection against MSK.

## Migration or Deployment Notes

1. Deploy chart `0.48.7` via normal GitOps path (no direct Helm upgrade).
2. **Prod OutOfSync for kafka is not fixed by re-enable.** After MSK is
   confirmed healthy:

```cmd
kubectl -n techx-corp-prod delete service kafka --ignore-not-found
kubectl -n techx-corp-prod delete statefulset kafka --ignore-not-found
```

3. Optional PVC reclaim (`kafka-data-kafka-0`) only after STS delete and data
   is no longer needed (retention policy Retain).
4. Same pattern for `valkey-cart` if ElastiCache cutover left orphans.

## Risks and Rollback

| Risk | Likelihood | Severity | Mitigation / Rollback |
|---|---|---|---|
| Operator deletes kafka while apps still use in-cluster DNS `kafka:9092` | Medium if MSK cutover incomplete | High | Verify `KAFKA_ADDR` secret and consumer config before delete |
| serviceName change restarts STS pods | Low | Medium | Single-replica broker; schedule during maintenance if needed |
| Deleting PVC loses residual in-cluster topic data | Medium if deleted carelessly | High | Doc marks PVC delete optional; MSK is source of truth in prod |

**Rollback procedure:**

* Revert this chart commit (restore empty volumes behavior / drop serviceName)
  via Git; Argo self-heals remaining rendered resources.
* Orphan objects already deleted stay deleted unless recreated by re-enabling
  the component in values (not recommended for prod).

<!-- Change trail: @hungxqt - 2026-07-16 - StatefulSet Argo drift fix + prod MSK kafka orphan cleanup docs. -->

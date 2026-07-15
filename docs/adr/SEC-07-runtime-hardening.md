# ADR SEC-07: Production runtime hardening with Gatekeeper

- Status: Accepted for staged rollout
- Date: 2026-07-15
- Owners: Platform Security and Platform Engineering
- Approver signature: Pending production audit and mentor acceptance
- Cutover commit: Pending

## Context

The production render contained eight unpinned BusyBox init-container images,
missing init-container resources, and Grafana's root `init-chown-data` container.
Static chart cleanup removes those known violations, but future manifests also
need an admission guardrail.

## Decision

Install Gatekeeper chart `3.23.0` through Terraform. Terraform owns the release,
CRDs, webhook, and namespace. Argo CD owns three policies:

- `K8sContainerHardening`: effective `runAsNonRoot=true` and capability drop `ALL`
  for containers, init containers, and ephemeral containers.
- `K8sAllowedImageTags`: fixed tags or valid SHA-256 digests; no missing tag or
  case-insensitive `latest`.
- `K8sRequiredResources`: CPU/memory requests and limits for containers and init
  containers. Kubernetes does not support resources on ephemeral containers.

Policies cover Pod, Deployment, StatefulSet, DaemonSet, ReplicaSet, Job,
CronJob, and ReplicationController. Only `kube-system`, `kube-public`,
`kube-node-lease`, and `gatekeeper-system` are excluded. Any future exception
must record owner, reason, expiry, and Platform Security approval.

The webhook is fail-closed and runs with two controller replicas, a PDB, and the
existing Critical MNG. Mutation, external data, and generated-resource expansion
are disabled. This adds no separately billed AWS service.

## Rollout and rollback

1. Deploy chart cleanup and verify workload health, storefront access boundaries,
   and flagd behavior.
2. Install Gatekeeper and apply policies with `enforcementAction: dryrun`.
3. Observe at least two audit cycles and record zero violations below.
4. Change all three constraints to `deny` in a separate reviewed commit.
5. Run the mentor rejection demo and sign this ADR.

For a false positive, revert constraints to `dryrun` through Git and Argo CD,
add a regression fixture, then repeat audit. If the fail-closed webhook is
unavailable, restore its controller first; fail-open is break-glass only and
requires approval plus an audit trail.

## Evidence

| Evidence | Result | Commit/time |
|---|---|---|
| Production Helm render compliance inventory | Pending deploy | Pending |
| Three constraints, two audit cycles, zero violations | Pending | Pending |
| Constraints switched to `deny` | Pending | Pending |
| Mentor invalid-manifest rejection | Pending | Pending |
| Storefront/private ops/flagd regression checks | Pending | Pending |

## Signatures

| Role | Name | Signature/date |
|---|---|---|
| Platform Engineering | @hungxqt | Pending |
| Platform Security |  | Pending |
| Service owner representative |  | Pending |

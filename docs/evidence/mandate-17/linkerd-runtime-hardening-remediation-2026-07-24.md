# Linkerd runtime-hardening blocker remediation report

Date: 2026-07-24
Cluster: `techx-tf2-prod`
Commit deployed: `d11d7e99ae56ab7a4e22a5f7b777a43a552aa21b`

## Summary

Mandate 17 reported seven runtime-hardening inventory findings caused by the
Mandate 16 Linkerd rollout:

- Six findings from `linkerd-init` initContainers adding `NET_ADMIN` and
  `NET_RAW` without `drop: ALL`.
- One finding from `linkerd-heartbeat` missing CPU/memory requests and limits.

The findings were valid. `linkerd-init` is expected when Linkerd runs without
CNI because it configures iptables. The remediation switches Linkerd to the
official CNI path and disables the optional telemetry heartbeat CronJob.

## Remediation

- Added GitOps Application `linkerd-cni` using Helm chart `linkerd2-cni`
  version `30.12.2`.
- Changed `linkerd-control-plane` sync wave from `1` to `2`, after CRDs and CNI.
- Set `cniEnabled: true` on `linkerd-control-plane`, removing
  `linkerd-init/proxy-init` from rendered control-plane workloads.
- Set `disableHeartBeat: true`, removing the optional `linkerd-heartbeat`
  CronJob.
- Added a narrow runtime-hardening inventory exception for
  `linkerd-cni/DaemonSet/linkerd-cni` because the CNI plugin must write to host
  CNI paths `/opt/cni/bin` and `/etc/cni/net.d`.
- Added `linkerd-cni` to the production runtime-hardening migration namespace
  exclusion so the reviewed CNI DaemonSet can be admitted.

## Local verification

Commands:

```sh
helm lint . -f values.yaml -f values-public-alb.yaml -f values-prod.yaml
kubectl kustomize gitops/runtime-hardening/overlays/enforce-clusterwide-prod-audit
helm template linkerd-control-plane linkerd-control-plane \
  --repo https://helm.linkerd.io/stable \
  --version 1.16.11 \
  --namespace linkerd \
  -f <valuesObject from gitops/linkerd/linkerd-control-plane.yaml>
helm template linkerd-cni linkerd2-cni \
  --repo https://helm.linkerd.io/stable \
  --version 30.12.2 \
  --namespace linkerd-cni \
  -f <valuesObject from gitops/linkerd/linkerd-cni.yaml>
```

Results:

- Helm lint passed.
- Runtime-hardening production overlay rendered 6 bindings:
  3 `Deny`, 3 `Warn/Audit`.
- Linkerd control-plane render had `linkerd-init=0`.
- Linkerd control-plane render had `linkerd-heartbeat=0`.
- Linkerd CNI DaemonSet rendered with resources:
  requests `10m/32Mi`, limits `100m/128Mi`.
- Simulated Linkerd/CNI runtime-hardening inventory returned
  `simulated_linkerd_inventory_violations=0`.

Note: PowerShell verifier scripts were not run locally because `pwsh` is not
installed on the workstation. Equivalent Helm, Kustomize, and render assertions
were run instead.

## Live verification

ArgoCD Application state after refresh:

```text
NAME                    SYNC STATUS   HEALTH STATUS   REVISION
root-prod               Synced        Healthy         d11d7e99ae56ab7a4e22a5f7b777a43a552aa21b
linkerd                 Synced        Healthy         d11d7e99ae56ab7a4e22a5f7b777a43a552aa21b
linkerd-cni             Synced        Healthy         30.12.2
linkerd-control-plane   Synced        Healthy         1.16.11
runtime-hardening       Synced        Healthy         d11d7e99ae56ab7a4e22a5f7b777a43a552aa21b
techx-corp              Synced        Healthy         d11d7e99ae56ab7a4e22a5f7b777a43a552aa21b
```

Linkerd blocker checks:

```text
linkerd-destination init=linkerd-network-validator,
linkerd-identity init=linkerd-network-validator,
linkerd-proxy-injector init=linkerd-network-validator,
```

`linkerd-init` is no longer present. The remaining
`linkerd-network-validator` initContainer is expected for the CNI path.

Heartbeat check:

```text
Error from server (NotFound): cronjobs.batch "linkerd-heartbeat" not found
```

Linkerd CNI check:

```text
NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
linkerd-cni   7         7         7       7            7

resources:
  limits:   cpu=100m, memory=128Mi
  requests: cpu=10m, memory=32Mi
host paths:
  /opt/cni/bin
  /etc/cni/net.d
```

Runtime-hardening inventory Job:

```sh
kubectl -n techx-corp-prod create job \
  --from=cronjob/runtime-hardening-inventory \
  runtime-hardening-inventory-m16-062425
kubectl -n techx-corp-prod wait \
  --for=condition=complete \
  job/runtime-hardening-inventory-m16-062425 \
  --timeout=180s
kubectl -n techx-corp-prod logs job/runtime-hardening-inventory-m16-062425
```

Result:

```json
{
  "checkedContainers": 91,
  "checkedObjects": 60,
  "cluster": "techx-tf2-prod",
  "environment": "production",
  "status": "pass",
  "violationCount": 0,
  "violations": []
}
```

## Conclusion

The Mandate 16 Linkerd runtime-hardening blockers are remediated in production.
ArgoCD is Synced/Healthy at commit `d11d7e9`, Linkerd CNI is Healthy, the
heartbeat CronJob is removed, `linkerd-init` is no longer rendered in the
Linkerd control plane, and a fresh runtime-hardening inventory Job completed
with `violationCount=0`.

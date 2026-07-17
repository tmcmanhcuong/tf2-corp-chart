# Directive #8 managed data cutover

This runbook moves production PostgreSQL, Valkey, and Kafka to private AWS
managed services without changing flagd or the public storefront path. Record
all timestamps in UTC and place command output under `docs/evidence/directive-08/`.

## Safety gates

Do not cut over a store unless all of these are true:

- Terraform plan contains only the reviewed managed-data changes.
- Source and target inventories have been captured.
- Target TLS and authentication checks pass from an EKS migration pod.
- Replication lag is zero or within the approved bound.
- Checkout success is at least 99% for the 30-minute baseline window.
- The rollback operator and exact previous Helm/Argo revision are recorded.

Freeze unrelated production promotion during each cutover. Cut over one store
at a time and observe it for at least 60 minutes before continuing.

## 1. Provision and bootstrap

Apply `tf2-corp-infra/environments/production`. Confirm:

```bash
aws rds describe-db-instances --db-instance-identifier techx-prod-tf2-postgresql
aws elasticache describe-replication-groups --replication-group-id techx-prod-tf2-cart
aws kafka describe-cluster-v2 --cluster-arn "$(terraform output -raw msk_cluster_arn)"
```

Retrieve the RDS-managed master secret only into the operator shell. Never put
it in Git or command output. Create the application role using the username and
password already stored in `techx-corp/production/postgresql-app`, then grant
only the existing application database/schema privileges.

Deploy the secrets chart with `values-prod.yaml`. Verify the resulting Secrets
by key name only; never print values:

```bash
kubectl -n techx-corp-prod get externalsecret,secret
kubectl -n techx-corp-prod get secret techx-corp-postgresql-app -o json | jq -r '.data | keys[]'
kubectl -n techx-corp-prod get secret techx-corp-msk -o json | jq -r '.data | keys[]'
```

## 2. PostgreSQL full load and CDC

Use AWS DMS full-load plus CDC for the no-downtime path. Enable logical
replication on the temporary source only for the migration window. Load schema
first with `pg_dump --schema-only`; DMS then copies rows and streams changes.

Required sequence:

1. Capture the source schema, table counts, sequence values, and checksums.
2. Restore schema and seed objects to RDS.
3. Start DMS full-load-and-cdc and wait for `Full load complete`.
4. Wait until CDC latency is below five seconds and no table has an error.
5. Run `scripts/directive-08/postgres-parity.sql` against source and target.
6. Restart only Accounting, Product Catalog, and Product Reviews with RDS DSNs.
7. Run read/write smoke tests and repeat parity.
8. Stop DMS only after the 60-minute observation window.

Rollback before source retirement: restore the previous secrets-chart revision,
roll the three clients, and verify they write to the source. If writes have
already occurred only on RDS, reverse-replicate or export those rows before
rollback. Never silently discard target-only writes.

## 3. Valkey parity and failover

For a fresh migration use RIOT/redis-shake with continuous replication. The
current production endpoint already uses ElastiCache, so reconstruct evidence
from the retained source before deleting its PVC:

```bash
scripts/directive-08/valkey-parity.sh "$SOURCE_URI" "$TARGET_URI"
aws elasticache test-failover \
  --replication-group-id techx-prod-tf2-cart \
  --node-group-id 0001
```

Record `DBSIZE`, key type counts, TTL buckets, and the deterministic digest.
Run add-to-cart and checkout throughout failover. Roll back by restoring the
previous Cart endpoint only after synchronizing target-only keys back to the
source; a session reset is not an acceptable silent rollback.

## 4. Kafka topic and offset migration

Create `orders`, `orders-approved`, `orders-cancelled`, and `orders-shipped` on
MSK with the source partition count and replication factor two. Run MirrorMaker
2 from the in-cluster broker to MSK, including consumer-group offsets.

1. Capture source topic configs, partition start/end offsets, and group offsets.
2. Start MirrorMaker 2 and wait for replication lag to reach zero.
3. Run `scripts/directive-08/kafka-parity.sh` for source and target.
4. Start canary consumers on MSK without committing production group offsets.
5. Switch Checkout/outbox producer to MSK.
6. Switch Fraud Detection and Accounting consumer groups to MSK.
7. Confirm outbox pending records drain and consumer lag remains bounded.
8. Stop source producers, take final offsets, and keep the broker read-only for
   the observation window.

Consumers must remain idempotent because replay can deliver an event more than
once. Rollback restores the previous chart revision and resumes source groups
from recorded offsets. Mirror target-only messages back before reopening source
writes.

## 5. Disable self-hosted stores

After all three observation windows and parity checks pass, sync the production
overlay. It sets `postgresql`, `valkey-cart`, and `kafka` to `enabled: false`.

```bash
kubectl -n techx-corp-prod get pod,sts,svc | tee post-cutover-kubernetes.txt
kubectl -n techx-corp-prod get hpa
```

There must be no PostgreSQL, Valkey, or Kafka Pod/StatefulSet/Service. Retain
PVCs until mentor sign-off and the approved rollback window expires.

## 6. Acceptance evidence

Attach:

- AWS status, private subnet, security group, KMS, TLS, backup, and Multi-AZ evidence.
- Pre/post PostgreSQL row counts, sequence values, and checksums.
- Pre/post Valkey key counts, TTL/type inventory, and digest.
- Pre/post Kafka topic configs, offsets, message counts, and consumer lag.
- Checkout success and latency charts covering every cutover window.
- Argo revision and Kubernetes inventory proving all three data Pods are absent.
- The cost table and tested rollback decisions.
- Mentor name, UTC timestamp, and confirmation.


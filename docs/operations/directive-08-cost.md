# Directive #8 cost decision

Production uses the smallest HA-capable starting sizes that match the measured
demo workload. Validate current regional prices in AWS Pricing Calculator and
attach the exported estimate before approval; this document intentionally does
not hard-code prices that can drift.

| Store | Production choice | Reliability decision |
|---|---|---|
| PostgreSQL | Multi-AZ `db.t4g.small`, 20 GiB gp3, autoscale to 100 GiB | Accounting/revenue records require synchronous standby, PITR, and final snapshots. |
| Valkey | 2 x `cache.t4g.micro` | Cart requires automatic cross-AZ failover; one node would preserve the SPOF. |
| Kafka | 2 x `kafka.t3.small`, 10 GiB each | Two-AZ replication is the minimum managed queue posture for this workload. |

The weekly estimate must include instance hours, storage, backup overage,
CloudWatch ingestion/retention, KMS requests, and cross-AZ transfer. DMS and
MirrorMaker are temporary migration costs and must be removed after sign-off.
The go/no-go threshold is a total TF forecast below USD 300/week, with AWS
Budget alerts configured before cutover.

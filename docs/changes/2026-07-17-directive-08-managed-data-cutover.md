# Directive #8 managed data cutover

The production overlay now disables the in-cluster PostgreSQL, Valkey, and
Kafka components. PostgreSQL application DSNs are assembled by External
Secrets from existing application credentials plus Terraform-managed RDS
metadata and require full TLS certificate verification. MSK Secrets now include
SCRAM credentials, and Checkout, Accounting, and Fraud Detection consume them
through `secretKeyRef` only.

The operational package adds a staged cutover and rollback runbook, cost
decision, PostgreSQL row/checksum parity SQL, Valkey key/digest parity, and
Kafka topic/offset capture. PVC deletion remains explicitly gated on parity,
checkout SLO >= 99%, the observation window, and mentor sign-off.


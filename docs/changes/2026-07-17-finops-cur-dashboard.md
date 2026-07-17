# Change: Add FinOps CUR Cost Dashboard

## Summary

Added a provisioned Grafana Amazon Athena datasource and a CUR-backed FinOps dashboard for production cost visibility. The dashboard focuses on the already-applied CUR analytics path and does not depend on Cost Optimization Hub recommendation exports.

## Context

The infrastructure repo now provisions:

- CUR S3 path: `s3://company-cdo-493499579600-telemetry/cur/finops-watch-cur/data/`
- Glue database: `finops_cur`
- Athena workgroup: `grafana-cur`
- Grafana IRSA role: `arn:aws:iam::493499579600:role/techx-prod-tf2-grafana-athena`

Cost Optimization Hub recommendation export remains disabled in infrastructure because AWS rejected exports against `COST_OPTIMIZATION_RECOMMENDATIONS` for the current account. CUR dashboards are unaffected.

## Implementation

- Added Grafana plugin `grafana-athena-datasource`.
- Added Athena datasource provisioning:
  - `grafana/provisioning/datasources/athena-cur.yaml`
  - UID: `finops-athena-cur`
  - Auth: AWS SDK default provider chain.
  - Catalog/database/workgroup: `AwsDataCatalog` / `finops_cur` / `grafana-cur`.
- Added production Grafana service account IRSA annotation in `values-prod.yaml`.
- Added dashboard:
  - `grafana/provisioning/dashboards/finops-cur-cost-overview.json`

## Dashboard Panels

| Panel | Purpose |
|---|---|
| Month-to-date spend | Current monthly spend from CUR. |
| Budget used | Percent of the $900 monthly guardrail. |
| Projected month-end | Run-rate projection from current MTD spend. |
| Today spend | Daily guardrail view against $45. |
| Daily cost trend | Cost movement across the dashboard time range. |
| Top services by cost | Main service cost drivers. |
| Cumulative monthly spend | Month-to-date accumulation curve. |
| Daily guardrail breach candidates | Days with spend at or above $45. |
| Daily cost by top 5 services | Service-level trend for dominant cost drivers. |

## Operator Notes

- The dashboard has a `cur_table` textbox variable defaulting to `finops_watch_cur`.
- If the Glue crawler creates a different table name, update the dashboard variable in Grafana.
- The dashboard requires Grafana to run in production with the IRSA role from the infrastructure repo.
- Athena query cost is bounded by the `grafana-cur` workgroup bytes cutoff.

## Validation

- JSON dashboard parses successfully.
- Helm render should include:
  - `grafana-dashboard-finops-cur-cost-overview`
  - `grafana-datasources`
  - Grafana service account annotation in production values.

## Rollback

Remove the Athena datasource file, the dashboard JSON, the Athena plugin entry, and the production Grafana service account annotation.

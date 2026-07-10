#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# create-secrets.sh
# Tạo các secret trong AWS Secrets Manager cho TechX Corp Platform.
#
# Script này chạy 1 lần khi setup môi trường mới.
# KHÔNG commit giá trị thật vào git - truyền qua environment variables.
#
# Cách dùng:
#   export CLUSTER_NAME=techx-tf2
#   export AWS_REGION=us-east-1
#   export POSTGRES_USER=<giá trị thật>
#   export POSTGRES_PASSWORD=<giá trị thật>
#   export DB_PASSWORD=<giá trị thật>          # password của user otelu
#   export GRAFANA_ADMIN_USER=<giá trị thật>
#   export GRAFANA_ADMIN_PASSWORD=<giá trị thật>
#   export FLAGD_SECRET_KEY_BASE=<giá trị thật>
#   bash scripts/create-secrets.sh
#
# Yêu cầu: aws CLI đã login, có quyền secretsmanager:CreateSecret
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME is required}"
AWS_REGION="${AWS_REGION:?AWS_REGION is required}"

POSTGRES_USER="${POSTGRES_USER:?POSTGRES_USER is required}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER is required}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD is required}"
FLAGD_SECRET_KEY_BASE="${FLAGD_SECRET_KEY_BASE:?FLAGD_SECRET_KEY_BASE is required}"

PREFIX="${CLUSTER_NAME}"

echo "Creating secrets in AWS Secrets Manager (region: ${AWS_REGION}, prefix: ${PREFIX})"

# ── 1. postgres-credentials ──────────────────────────────────────
# Dùng bởi: postgresql pod (POSTGRES_USER, POSTGRES_PASSWORD)
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "${PREFIX}/postgres-credentials" \
  --description "PostgreSQL root credentials for TechX Corp (${CLUSTER_NAME})" \
  --secret-string "{
    \"postgres-user\": \"${POSTGRES_USER}\",
    \"postgres-password\": \"${POSTGRES_PASSWORD}\"
  }" || \
aws secretsmanager put-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${PREFIX}/postgres-credentials" \
  --secret-string "{
    \"postgres-user\": \"${POSTGRES_USER}\",
    \"postgres-password\": \"${POSTGRES_PASSWORD}\"
  }"

echo "✓ Created: ${PREFIX}/postgres-credentials"

# ── 2. app-db-credentials ─────────────────────────────────────────
# Dùng bởi: accounting, product-catalog, product-reviews
# Connection string được build sẵn để không cần sửa app code
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "${PREFIX}/app-db-credentials" \
  --description "Application DB credentials for TechX Corp services (${CLUSTER_NAME})" \
  --secret-string "{
    \"db-password\": \"${DB_PASSWORD}\",
    \"accounting-connection-string\": \"Host=postgresql;Username=otelu;Password=${DB_PASSWORD};Database=otel\",
    \"product-catalog-connection-string\": \"postgres://otelu:${DB_PASSWORD}@postgresql/otel?sslmode=disable\",
    \"product-reviews-connection-string\": \"host=postgresql user=otelu password=${DB_PASSWORD} dbname=otel\"
  }" || \
aws secretsmanager put-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${PREFIX}/app-db-credentials" \
  --secret-string "{
    \"db-password\": \"${DB_PASSWORD}\",
    \"accounting-connection-string\": \"Host=postgresql;Username=otelu;Password=${DB_PASSWORD};Database=otel\",
    \"product-catalog-connection-string\": \"postgres://otelu:${DB_PASSWORD}@postgresql/otel?sslmode=disable\",
    \"product-reviews-connection-string\": \"host=postgresql user=otelu password=${DB_PASSWORD} dbname=otel\"
  }"

echo "✓ Created: ${PREFIX}/app-db-credentials"

# ── 3. grafana-admin ──────────────────────────────────────────────
# Dùng bởi: grafana subchart (admin.existingSecret)
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "${PREFIX}/grafana-admin" \
  --description "Grafana admin credentials for TechX Corp (${CLUSTER_NAME})" \
  --secret-string "{
    \"admin-user\": \"${GRAFANA_ADMIN_USER}\",
    \"admin-password\": \"${GRAFANA_ADMIN_PASSWORD}\"
  }" || \
aws secretsmanager put-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${PREFIX}/grafana-admin" \
  --secret-string "{
    \"admin-user\": \"${GRAFANA_ADMIN_USER}\",
    \"admin-password\": \"${GRAFANA_ADMIN_PASSWORD}\"
  }"

echo "✓ Created: ${PREFIX}/grafana-admin"

# ── 4. flagd-ui-secret ────────────────────────────────────────────
# Dùng bởi: flagd sidecar container (Phoenix SECRET_KEY_BASE)
aws secretsmanager create-secret \
  --region "${AWS_REGION}" \
  --name "${PREFIX}/flagd-ui-secret" \
  --description "flagd-ui Phoenix secret key base for TechX Corp (${CLUSTER_NAME})" \
  --secret-string "{
    \"secret-key-base\": \"${FLAGD_SECRET_KEY_BASE}\"
  }" || \
aws secretsmanager put-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${PREFIX}/flagd-ui-secret" \
  --secret-string "{
    \"secret-key-base\": \"${FLAGD_SECRET_KEY_BASE}\"
  }"

echo "✓ Created: ${PREFIX}/flagd-ui-secret"

echo ""
echo "All secrets created successfully."
echo ""
echo "Next steps:"
echo "  1. terraform apply (tf2-corp-infra) to create ESO IAM role"
echo "  2. terraform output -raw eso_role_arn  → copy ARN"
echo "  3. Fill ARN into values.yaml: external-secrets.serviceAccount.annotations"
echo "  4. helm repo add external-secrets https://charts.external-secrets.io"
echo "  5. helm dependency update ./tf2-corp-chart"
echo "  6. helm upgrade --install techx-corp ./tf2-corp-chart ..."

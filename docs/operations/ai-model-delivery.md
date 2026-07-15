# AI guardrail model delivery

The product-reviews image contains runtime libraries but not Hugging Face model
weights. Each pod downloads a pinned, checksum-verified cache artifact from a
private S3 bucket into an `emptyDir` before the application starts.

## One-time development bootstrap

1. Apply `tf2-corp-infra/environments/development`. Record outputs
   `ai_model_bucket_name` and `ai_model_service_account_role_arn`.
2. In `tf2-corp-platform`, build the pinned artifact:

   ```powershell
   .\src\product-reviews\.venv\Scripts\python.exe `
     src\product-reviews\scripts\build_model_artifact.py
   ```

3. Upload all three immutable files. Write the checksum with **Unix LF** line
   endings only (not Windows CRLF). GNU `sha256sum -c` treats a trailing `\r`
   as part of the filename and fails with `No such file or directory`.

   ```powershell
   $revision = "89b085cd330414d3e7d9dd787870f315957e1e9f"
   $prefix = "s3://techx-dev-tf2-ai-models-493499579600/protectai/deberta-v3-base-prompt-injection-v2/$revision"
   # Ensure LF-only checksum before upload (PowerShell on Windows):
   $sha = Get-Content -Raw dist/ai-model/model.tar.gz.sha256
   $sha = ($sha -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd() + "`n"
   [IO.File]::WriteAllText((Resolve-Path dist/ai-model/model.tar.gz.sha256), $sha, (New-Object System.Text.UTF8Encoding $false))
   aws s3 cp dist/ai-model/model.tar.gz "$prefix/model.tar.gz"
   aws s3 cp dist/ai-model/model.tar.gz.sha256 "$prefix/model.tar.gz.sha256"
   aws s3 cp dist/ai-model/manifest.json "$prefix/manifest.json"
   ```

4. Merge/sync this chart only after the objects exist. The init containers block
   startup on download, checksum, extraction, or marker validation failure.

## Init container notes

Model bootstrap uses **two** init containers (shared `tmp-dir` and
`ai-model-cache` volumes):

| Init | Image | Role |
|---|---|---|
| `fetch-ai-guardrail-model` | `modelDelivery.fetcherImage` (AWS CLI) | `aws s3 cp` archive + `.sha256`, strip CR from checksum, `sha256sum -c` |
| `extract-ai-guardrail-model` | `modelDelivery.extractorImage` (busybox) | `tar -xzf` into `/models`, require `.model-ready`, remove archive from `/tmp` |

The official AWS CLI image provides `aws` and `sha256sum` but **does not** ship
`tar`, so extraction cannot run in the same container.

The AWS CLI fetcher runs with `readOnlyRootFilesystem: true`. It sets
`HOME=/tmp` (and AWS config paths under `/tmp`) so credential cache writes go
to the pod `tmp-dir` emptyDir rather than `/.aws` on the read-only root.

The fetch init also runs `sed -i 's/\r$//'` on the checksum file so a
Windows-uploaded `.sha256` does not break `sha256sum -c`.

## Verification

```cmd
kubectl -n techx-corp-prod rollout status deployment/product-reviews --timeout=10m
kubectl -n techx-corp-prod logs deployment/product-reviews -c fetch-ai-guardrail-model
kubectl -n techx-corp-prod logs deployment/product-reviews -c extract-ai-guardrail-model
kubectl -n techx-corp-prod get pod -l opentelemetry.io/name=product-reviews
```

Dev namespace: replace `techx-corp-prod` with `techx-corp-dev`.

Rollback the chart revision to restore the previous pod specification. Do not
overwrite an existing revision path; publish a new revision and update `s3Uri`.

<!-- Change trail: @hungxqt - 2026-07-15 - Document aws-cli/busybox split init and LF checksum requirement. -->

# Change: Route production product reviews to Groq

## Summary

Production `product-reviews` now uses Groq's OpenAI-compatible endpoint directly
with the `openai/gpt-oss-20b` model. Development defaults continue to use the
in-cluster `llm` service.

## Configuration

`values-prod.yaml` overrides only:

- `LLM_BASE_URL=https://api.groq.com/openai/v1`
- `LLM_MODEL=openai/gpt-oss-20b`

`OPENAI_API_KEY` remains sourced from the `techx-corp-product-reviews`
Kubernetes Secret. No credential value is stored in this repository.

## Operational dependency

Before rollout, the production operator must:

1. Put the Groq API key in AWS Secrets Manager at
   `techx-corp/production/product-reviews` under `OPENAI_API_KEY`.
2. Confirm External Secrets has synchronized `techx-corp-product-reviews`.
3. Confirm the workload can resolve and reach `api.groq.com` over HTTPS.

## Validation and rollback

Render the production chart and confirm the endpoint/model overrides coexist
with the `OPENAI_API_KEY` `secretKeyRef`. After rollout, run the AI grounding,
prompt-injection, PII and provider-failure smoke tests.

Rollback by reverting the two production overrides so the service uses the
in-cluster `llm` endpoint and `techx-llm` model again.

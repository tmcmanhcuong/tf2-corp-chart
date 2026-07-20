# MANDATE 10 AUDIT EVIDENCE REPORT (Secure Delivery Pipeline)

Tài liệu báo cáo chứng cứ nghiệm thu Mandate 10 - Chuỗi cung ứng phần mềm an toàn (Secure Delivery Pipeline).

---

## 📋 Summary of Acceptance Criteria (DoD)

| Kịch bản kiểm thử | Công cụ / Cổng chặn | Kết quả mong đợi | Trạng thái Nghiệm thu |
| :--- | :--- | :--- | :--- |
| **Kịch bản 1: PR Gate (CI Fail)** | GitHub Actions + Branch Protection | CI quét thấy lỗi CVE High/Secret/SAST ➡️ **Chặn merge PR** | **PASS** |
| **Kịch bản 2: VAP Gate (Tag Image)** | K8s Native ValidatingAdmissionPolicy | Deploy pod dùng tag `:latest` hoặc `:v1.0` ➡️ API Server từ chối: **Format Must Be Digest** | **PASS** |
| **Kịch bản 3: Signature Gate (Unsigned)** | Sigstore Policy-Controller + AWS KMS | Deploy pod dùng digest nhưng chưa ký Cosign ➡️ Admission Controller từ chối: **No Valid KMS Signature** | **PASS** |
| **Kịch bản 4: Full Traceability** | PowerShell `trace-provenance.ps1` | Chạy script trên Pod thành công ➡️ **Trích xuất full Digest, KMS Signer, SBOM & PR Approver** | **PASS** |

---

## 🧪 Detailed Test Execution Logs

### Kịch bản 1: CI Pipeline Security Gate
*   **Lệnh thử nghiệm:** Tạo PR cố tình chèn thêm Secret giả lập hoặc code SAST lỗi vào `src/payment/`.
*   **Kết quả:** Workflow `ci.yml` kích hoạt `semgrep` và `trufflehog`, phát hiện lỗi và trả về exit code `1`. GitHub Status Check báo đỏ `CI / Failed`, nút Merge PR bị khóa xám theo luật Branch Protection.

### Kịch bản 2: Native VAP Tag Blocking
*   **Lệnh thử nghiệm:**
    ```bash
    kubectl apply -f tests/mandate10/test-scenario-2-vap-tag-blocked.yaml
    ```
*   **Kết quả thực tế từ K8s API Server:**
    ```text
    Error from server (Forbidden): error when creating "tests/mandate10/test-scenario-2-vap-tag-blocked.yaml": 
    pods "test-vap-tag-blocked" is forbidden: ValidatingAdmissionPolicy 'runtime-hardening-pod.techx.io' 
    with binding 'runtime-hardening-pod-enforce.techx.io' denied request: 
    Container images must use a SHA-256 digest (kube-system supports fixed tags); latest and untagged images are forbidden.
    ```

### Kịch bản 3: Sigstore Policy-Controller Signature Blocking
*   **Lệnh thử nghiệm:**
    ```bash
    kubectl apply -f tests/mandate10/test-scenario-3-unsigned-digest-blocked.yaml
    ```
*   **Kết quả thực tế từ Sigstore Admission Controller:**
    ```text
    Error from server (Forbidden): error when creating "tests/mandate10/test-scenario-3-unsigned-digest-blocked.yaml": 
    admission webhook "policy.sigstore.dev" denied the request: 
    validation failed for image 493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-prod-corp/payment@sha256:e66264b9... 
    against policy 'ecr-signature-policy': no matching signatures found for authority 'key' using KMS awskms:///alias/tf2-cosign-signing-key
    ```

### Kịch bản 4: Full Provenance Traceability
*   **Lệnh thử nghiệm:**
    ```powershell
    .\scripts\trace-provenance.ps1 -PodName payment-7f94c8b9d-x2k9z -Namespace techx-corp-prod
    ```
*   **Kết quả xuất báo cáo audit:**
    ```text
    =========================================================
    TRACE PROVENANCE FOR POD: payment-7f94c8b9d-x2k9z IN NAMESPACE: techx-corp-prod
    =========================================================

    [Container: payment]
      Image Name: 493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-prod-corp/payment@sha256:496ed496...
      Image ID:   493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-prod-corp/payment@sha256:496ed496...
      Detected Digest: sha256:496ed4962e36a9c31bbe3d12e867dfdc3c6e768433e895846bd3c049d59fb903
      Image Ref for Cosign: 493499579600.dkr.ecr.us-east-1.amazonaws.com/techx-prod-corp/payment@sha256:496ed496...
      --> Verifying Cosign Signature using AWS KMS...
      [SUCCESS] Signature verified successfully against KMS key!
      --> Fetching Cosign Attestations (SBOM & Provenance)...
      [Attestation #0] Type: https://cosign.sigstore.dev/attestation/v1
        Format: SBOM (CycloneDX / SPDX)
        Details: SBOM attached successfully in ECR.
      [Attestation #1] Type: https://slsa.dev/provenance/v0.2
        Format: Custom Provenance (SLSA-like)
        - Commit SHA:  2e29e43f867b6ffecd828a1ecdc50d0a025285b50
        - PR Number:   #42
        - Approver:    @vuhoang186
        - Scan Status: PASSED (Trivy CVE: 0 High/Critical, Semgrep: 0 findings)
    ```

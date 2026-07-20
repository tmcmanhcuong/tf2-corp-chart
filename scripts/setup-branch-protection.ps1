[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Repo = "tf2-team/tf2-corp-platform",

    [Parameter(Mandatory = $false)]
    [string]$Branch = "main"
)

Write-Host "Setting up GitHub Branch Protection Rules for $Repo (Branch: $Branch)..." -ForegroundColor Cyan

# Requires gh CLI to be logged in
try {
    $payload = @{
        required_status_checks = @{
            strict = $true
            contexts = @(
                "ci / semgrep",
                "ci / trufflehog",
                "build-and-push / trivy",
                "build-and-push / release-ready"
            )
        }
        enforce_admins = $false
        required_pull_request_reviews = @{
            dismiss_stale_reviews = $true
            require_code_owner_reviews = $false
            required_approving_review_count = 1
        }
        restrictions = $null
    } | ConvertTo-Json -Depth 5

    Write-Host "Applying Branch Protection payload via GitHub REST API..." -ForegroundColor Gray
    $payload | gh api -X PUT "repos/$Repo/branches/$Branch/protection" --input -
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[SUCCESS] Branch protection successfully enabled for $Repo ($Branch)!" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to set branch protection. Make sure gh CLI is authenticated and has admin rights." -ForegroundColor Red
    }
} catch {
    Write-Error "Error setting branch protection: $_"
}

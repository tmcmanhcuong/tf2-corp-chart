param(
    [string]$Helm = "helm"
)

$ErrorActionPreference = "Stop"
$chartRoot = Split-Path -Parent $PSScriptRoot
$valueFiles = @(
    (Join-Path $chartRoot "values.yaml"),
    (Join-Path $chartRoot "values-public-alb.yaml"),
    (Join-Path $chartRoot "values-prod.yaml")
)

$helmArgs = @(
    "template", "techx-corp", $chartRoot,
    "--namespace", "techx-corp-prod"
)
foreach ($valueFile in $valueFiles) {
    $helmArgs += @("--values", $valueFile)
}

$renderedLines = & $Helm @helmArgs
if ($LASTEXITCODE -ne 0) {
    throw "helm template failed with exit code $LASTEXITCODE"
}
$documents = (($renderedLines -join "`n") -split "(?m)^---\s*$")

function Get-Manifest {
    param([string]$Kind, [string]$Name)

    $kindPattern = "(?m)^kind: $([regex]::Escape($Kind))$"
    $namePattern = "(?m)^  name: $([regex]::Escape($Name))$"
    return @($documents | Where-Object {
        $_ -match $kindPattern -and $_ -match $namePattern
    })
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$criticalServices = @(
    "ad", "cart", "checkout", "currency", "email", "flagd", "frontend",
    "frontend-proxy", "image-provider", "payment", "product-catalog",
    "product-reviews", "quote", "recommendation", "shipping"
)

foreach ($name in $criticalServices) {
    [array]$deployment = @(Get-Manifest -Kind "Deployment" -Name $name)
    if ($deployment.Count -ne 1) {
        throw "${name}: expected exactly one Deployment, found $($deployment.Count)"
    }

    [array]$hpa = @(Get-Manifest -Kind "HorizontalPodAutoscaler" -Name $name)
    if ($hpa.Count -eq 1) {
        Assert-Match $hpa[0] "(?m)^  minReplicas: 2$" "${name}: HPA floor must be 2"
    }
    else {
        Assert-Match $deployment[0] "(?m)^  replicas: 2$" "${name}: fixed replica floor must be 2"
    }

    [array]$pdb = @(Get-Manifest -Kind "PodDisruptionBudget" -Name $name)
    if ($pdb.Count -ne 1) {
        throw "${name}: expected exactly one PodDisruptionBudget"
    }
    Assert-Match $pdb[0] "(?m)^  minAvailable: 1$" "${name}: PDB minAvailable must be 1"
    Assert-Match $deployment[0] "(?ms)^  strategy:\s+rollingUpdate:\s+maxSurge: 1\s+maxUnavailable: 0\s+type: RollingUpdate" "${name}: unsafe rolling update strategy"
    Assert-Match $deployment[0] "(?m)^      terminationGracePeriodSeconds: 30$" "${name}: termination grace must be 30 seconds"
    Assert-Match $deployment[0] "(?ms)^          readinessProbe:.*?          lifecycle:\s+preStop:\s+sleep:\s+seconds: 10" "${name}: readiness and native preStop drain hook are required"
    Assert-Match $deployment[0] "(?ms)^      topologySpreadConstraints:.*?topologyKey: topology.kubernetes.io/zone\s+whenUnsatisfiable: DoNotSchedule\s+minDomains: 2.*?topologyKey: kubernetes.io/hostname\s+whenUnsatisfiable: DoNotSchedule\s+minDomains: 2" "${name}: hard two-AZ/two-host spread is required"

    Write-Host "PASS $name"
}

foreach ($name in @("kafka", "postgresql", "valkey-cart", "opensearch")) {
    [array]$statefulSet = @(Get-Manifest -Kind "StatefulSet" -Name $name)
    if ($statefulSet.Count -ne 1) {
        throw "${name}: expected exactly one StatefulSet"
    }
    Assert-Match $statefulSet[0] "(?m)^  replicas: 1$" "${name}: chart safety boundary expects the reviewed singleton architecture"
    if ((Get-Manifest -Kind "PodDisruptionBudget" -Name $name).Count -ne 0) {
        throw "${name}: do not render a misleading HA PDB for a singleton stateful service"
    }
}

[array]$publicIngress = @(Get-Manifest -Kind "Ingress" -Name "frontend-proxy-public")
if ($publicIngress.Count -ne 1) {
    throw "expected the public storefront Ingress"
}
Assert-Match $publicIngress[0] 'alb.ingress.kubernetes.io/scheme: "?internal"?' "Directive #1 regression: storefront origin ALB must remain internal"

Write-Host "Directive #3 production manifest policy checks passed."

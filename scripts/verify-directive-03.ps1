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

# Money-path / storefront stateless floor: two Ready replicas + PDB + hard spread.
$criticalServices = @(
    "ad", "cart", "checkout", "currency", "email", "frontend",
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

# flagd: reviewed singleton on Critical MNG (system-*), not multi-replica HA.
[array]$flagdDeployment = @(Get-Manifest -Kind "Deployment" -Name "flagd")
if ($flagdDeployment.Count -ne 1) {
    throw "flagd: expected exactly one Deployment, found $($flagdDeployment.Count)"
}
Assert-Match $flagdDeployment[0] "(?m)^  replicas: 1$" "flagd: fixed replica count must be 1 (singleton control plane)"
Assert-Match $flagdDeployment[0] "(?m)^        workload-class: critical$" "flagd: must pin to Critical MNG (workload-class=critical / system-*)"
if ($flagdDeployment[0] -match "(?m)^      topologySpreadConstraints:") {
    throw "flagd: singleton must not set topologySpreadConstraints"
}
if ((Get-Manifest -Kind "PodDisruptionBudget" -Name "flagd").Count -ne 0) {
    throw "flagd: do not render a multi-replica PDB for the flagd singleton"
}
Assert-Match $flagdDeployment[0] "(?ms)^  strategy:\s+rollingUpdate:\s+maxSurge: 1\s+maxUnavailable: 0\s+type: RollingUpdate" "flagd: unsafe rolling update strategy"
Assert-Match $flagdDeployment[0] "(?m)^      terminationGracePeriodSeconds: 30$" "flagd: termination grace must be 30 seconds"
Assert-Match $flagdDeployment[0] "(?ms)^          readinessProbe:.*?          lifecycle:\s+preStop:\s+sleep:\s+seconds: 10" "flagd: readiness and native preStop drain hook are required"
Write-Host "PASS flagd (singleton on critical)"

foreach ($name in @("kafka", "postgresql", "opensearch")) {
    [array]$statefulSet = @(Get-Manifest -Kind "StatefulSet" -Name $name)
    if ($statefulSet.Count -ne 1) {
        throw "${name}: expected exactly one StatefulSet"
    }
    Assert-Match $statefulSet[0] "(?m)^  replicas: 1$" "${name}: chart safety boundary expects the reviewed singleton architecture"
    if ((Get-Manifest -Kind "PodDisruptionBudget" -Name $name).Count -ne 0) {
        throw "${name}: do not render a misleading HA PDB for a singleton stateful service"
    }
}

if ((Get-Manifest -Kind "StatefulSet" -Name "valkey-cart").Count -ne 0) {
    throw "valkey-cart: production must use managed Multi-AZ Valkey, not the singleton StatefulSet"
}
$cartDeployment = (Get-Manifest -Kind "Deployment" -Name "cart")
Assert-Match $cartDeployment "(?ms)name: VALKEY_ADDR\s+value: valkey-cart.techx.internal:6379" "cart: managed Valkey address is required"
$checkoutDeployment = (Get-Manifest -Kind "Deployment" -Name "checkout")
Assert-Match $checkoutDeployment "(?ms)name: CHECKOUT_OUTBOX_TABLE\s+value: techx-prod-tf2-checkout-outbox" "checkout: durable outbox table is required"
Assert-Match $checkoutDeployment "(?m)^      serviceAccountName: checkout$" "checkout: dedicated IRSA ServiceAccount is required"
if ($checkoutDeployment -match "wait-for-kafka") {
    throw "checkout: Kafka must not block pod startup"
}

[array]$publicIngress = @(Get-Manifest -Kind "Ingress" -Name "frontend-proxy-public")
if ($publicIngress.Count -ne 1) {
    throw "expected the public storefront Ingress"
}
Assert-Match $publicIngress[0] 'alb.ingress.kubernetes.io/scheme: "?internal"?' "Directive #1 regression: storefront origin ALB must remain internal"

Write-Host "Directive #3 production manifest policy checks passed."

# Change trail: @hungxqt - 2026-07-15 - flagd singleton on Critical MNG; exclude from 2-replica floor.

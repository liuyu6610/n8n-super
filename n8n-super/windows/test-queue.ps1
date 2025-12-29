# windows/test-queue.ps1
#
# 作用：对 Queue 模式做可用性自检。
param(
  [string]$WebContainer = "n8n-web",
  [string]$WorkerContainer = "n8n-worker",
  [string]$WebhookContainer = "n8n-webhook",
  [string]$HealthUrl = "http://localhost:5678/healthz",
  [int]$TimeoutSeconds = 180
)

function Assert-LastExitCode {
  param(
    [string]$Step
  )
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed: $Step (exit=$LASTEXITCODE)"
    exit $LASTEXITCODE
  }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ok = $false

while ((Get-Date) -lt $deadline) {
  try {
    Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 5 -ErrorAction Stop | Out-Null
    $ok = $true
    break
  } catch {
    Start-Sleep -Seconds 2
  }
}

if (-not $ok) {
  Write-Error "Health check failed: $HealthUrl"
  exit 1
}

Write-Host "Health check OK: $HealthUrl"

$containers = @($WebContainer, $WorkerContainer, $WebhookContainer)
foreach ($c in $containers) {
  Write-Host "[check] container=$c"

  docker exec $c n8n --version
  Assert-LastExitCode "n8n --version ($c)"

  docker exec $c argocd version --client
  Assert-LastExitCode "argocd version --client ($c)"

  docker exec $c /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
  Assert-LastExitCode "python-fire import ($c)"
}

Write-Host "All queue checks passed."

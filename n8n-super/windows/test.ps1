# windows/test.ps1
#
# 作用：自检（单容器或 Queue 模式）（Windows/PowerShell）。
#
# 用法：
#   .\windows\test.ps1
#   .\windows\test.ps1 -Queue
param(
  [switch]$Queue,
  [string]$HealthUrl = "http://localhost:5678/healthz",
  [int]$TimeoutSeconds = 180,
  [string]$ContainerName = "n8n-super",
  [string]$WebContainer = "n8n-web",
  [string]$WorkerContainer = "n8n-worker",
  [string]$WebhookContainer = "n8n-webhook"
)

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ok = $false
while ((Get-Date) -lt $deadline) {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 5 | Out-Null
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

if ($Queue) {
  $containers = @($WebContainer, $WorkerContainer, $WebhookContainer)
  foreach ($c in $containers) {
    Write-Host "[check] container=$c"
    docker exec $c n8n --version
    docker exec $c argocd version --client
    docker exec $c /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
  }
  Write-Host "All queue checks passed."
} else {
  docker exec $ContainerName n8n --version
  docker exec $ContainerName argocd version --client
  docker exec $ContainerName /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
  docker exec $ContainerName node -e "const p=require('/home/node/.n8n/nodes/node_modules/n8n-nodes-python/package.json'); console.log(p.name+'@'+p.version)"
  Write-Host "All checks passed."
}

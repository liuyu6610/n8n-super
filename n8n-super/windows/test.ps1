# windows/test.ps1
#
# 作用：对单容器模式进行可用性自检。
#
# 检查项：
# - /healthz 轮询直到超时
# - n8n --version
# - argocd version --client
# - Python venv 基础依赖 python-fire import
# - 社区节点 n8n-nodes-python package.json 可读取
param(
  [string]$ContainerName = "n8n-super",
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

docker exec $ContainerName n8n --version
Assert-LastExitCode "n8n --version"

docker exec $ContainerName argocd version --client
Assert-LastExitCode "argocd version --client"

docker exec $ContainerName /opt/n8n-python-venv/bin/python -c "import fire; print('python-fire import ok')"
Assert-LastExitCode "python-fire import"

docker exec $ContainerName node -e "const p=require('/home/node/.n8n/nodes/node_modules/n8n-nodes-python/package.json'); console.log(p.name+'@'+p.version)"
Assert-LastExitCode "n8n-nodes-python package.json"

Write-Host "All checks passed."

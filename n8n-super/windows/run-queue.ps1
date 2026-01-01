# windows/run-queue.ps1
#
# 作用：启动 Queue 模式（docker-compose.queue.yml）。
#
# 默认行为：
# - Build: true（先 docker compose build）
# - Detached: true（后台 up -d）
param(
  [switch]$Build,
  [switch]$Detached,
  [switch]$Pull,
  [switch]$ForceRecreate
)

if (-not $PSBoundParameters.ContainsKey('Build')) { $Build = $true }
if (-not $PSBoundParameters.ContainsKey('Detached')) { $Detached = $true }
if (-not $PSBoundParameters.ContainsKey('Pull')) { $Pull = $false }
if (-not $PSBoundParameters.ContainsKey('ForceRecreate')) { $ForceRecreate = $false }

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$ComposeFile = Join-Path $RootDir "docker-compose.queue.yml"

if ($Build) {
  docker compose -f $ComposeFile build
}

if ($Pull) {
  docker compose -f $ComposeFile pull
}

$upArgs = @()
if ($ForceRecreate) {
  $upArgs += "--force-recreate"
}

if ($Detached) {
  docker compose -f $ComposeFile up -d @upArgs
} else {
  docker compose -f $ComposeFile up @upArgs
}

# windows/run.ps1
#
# 作用：启动单容器模式（docker-compose.yml）。
#
# 默认行为：
# - Build: true（先 docker compose build）
# - Detached: true（后台 up -d）
#
# 用法：
#   .\windows\run.ps1
#   .\windows\run.ps1 -Build:$false
#   .\windows\run.ps1 -Detached:$false
param(
  [switch]$Build,
  [switch]$Detached
)

if (-not $PSBoundParameters.ContainsKey('Build')) { $Build = $true }
if (-not $PSBoundParameters.ContainsKey('Detached')) { $Detached = $true }

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$ComposeFile = Join-Path $RootDir "docker-compose.yml"

if ($Build) {
  docker compose -f $ComposeFile build
}

if ($Detached) {
  docker compose -f $ComposeFile up -d
} else {
  docker compose -f $ComposeFile up
}

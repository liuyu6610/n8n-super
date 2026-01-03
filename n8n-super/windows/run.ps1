# windows/run.ps1
#
# 作用：启动 n8n（单容器或 Queue 模式）（Windows/PowerShell）。
#
# 用法：
#   .\windows\run.ps1
#   .\windows\run.ps1 -Queue
#   .\windows\run.ps1 -Pull -ForceRecreate
param(
  [switch]$Queue,
  [switch]$NoBuild,
  [switch]$NoDetach,
  [switch]$Pull,
  [switch]$ForceRecreate
)

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildEnvFile = Join-Path $RootDir "config\build.env"

if (Test-Path $BuildEnvFile) {
  Get-Content $BuildEnvFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line) { return }
    if ($line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    if (-not (Test-Path env:$k) -and $v) {
      Set-Item -Path env:$k -Value $v
    }
  }
}

$composeFile = Join-Path $RootDir "docker-compose.yml"
if ($Queue) {
  $queueComposeFile = Join-Path $RootDir "docker-compose-queue.yml"
  if (Test-Path $queueComposeFile) {
    $composeFile = $queueComposeFile
  } else {
    $composeFile = Join-Path $RootDir "docker-compose.queue.yml"
  }
}

if (-not $NoBuild) {
  docker compose -f $composeFile build
}

if ($Pull) {
  docker compose -f $composeFile pull
}

$upArgs = @()
if ($ForceRecreate) { $upArgs += "--force-recreate" }

if ($NoDetach) {
  docker compose -f $composeFile up @upArgs
} else {
  docker compose -f $composeFile up -d @upArgs
}

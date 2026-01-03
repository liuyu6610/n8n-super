# windows/build.ps1
#
# 作用：构建 n8n-super Docker 镜像（Windows/PowerShell）。
#
# 用法：
#   .\windows\build.ps1
#   .\windows\build.ps1 -Tag "n8n-super:1.78.1-r1"
param(
  [string]$Tag = "n8n-super:1.78.1",
  [string]$CommunityNodes = "",
  [string]$ArgoCdVersion = "",
  [string]$PipIndexUrl = "",
  [string]$PipExtraIndexUrl = "",
  [string]$PipTrustedHost = "",
  [string]$PipDefaultTimeout = ""
)

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildEnvFile = Join-Path $RootDir "config\build.env"
$BuildEnv = @{}

if (Test-Path $BuildEnvFile) {
  Get-Content $BuildEnvFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line) { return }
    if ($line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    if ($k) { $BuildEnv[$k] = $v }
  }
}

$buildArgs = @()

function Add-BuildArgIfPresent {
  param(
    [string]$Name,
    [string]$Value,
    [string]$EnvName1,
    [string]$EnvName2
  )

  if ($Value) {
    $buildArgs += "--build-arg"
    $buildArgs += "$Name=$Value"
    return
  }

  $envValue = ""
  if ($EnvName1 -and (Test-Path env:$EnvName1)) { $envValue = (Get-Item env:$EnvName1).Value }
  if (-not $envValue -and $EnvName2 -and (Test-Path env:$EnvName2)) { $envValue = (Get-Item env:$EnvName2).Value }
  if ($envValue) {
    $buildArgs += "--build-arg"
    $buildArgs += "$Name=$envValue"
    return
  }

  if ($BuildEnv.ContainsKey($Name) -and $BuildEnv[$Name]) {
    $buildArgs += "--build-arg"
    $buildArgs += "$Name=$($BuildEnv[$Name])"
  }
}

if ($CommunityNodes) {
  $buildArgs += "--build-arg"
  $buildArgs += "COMMUNITY_NODES=$CommunityNodes"
} elseif ($env:COMMUNITY_NODES) {
  $buildArgs += "--build-arg"
  $buildArgs += "COMMUNITY_NODES=$($env:COMMUNITY_NODES)"
} elseif ($BuildEnv.ContainsKey('COMMUNITY_NODES') -and $BuildEnv['COMMUNITY_NODES']) {
  $buildArgs += "--build-arg"
  $buildArgs += "COMMUNITY_NODES=$($BuildEnv['COMMUNITY_NODES'])"
}

if ($ArgoCdVersion) {
  $buildArgs += "--build-arg"
  $buildArgs += "ARGOCD_VERSION=$ArgoCdVersion"
} elseif ($env:ARGOCD_VERSION) {
  $buildArgs += "--build-arg"
  $buildArgs += "ARGOCD_VERSION=$($env:ARGOCD_VERSION)"
} elseif ($BuildEnv.ContainsKey('ARGOCD_VERSION') -and $BuildEnv['ARGOCD_VERSION']) {
  $buildArgs += "--build-arg"
  $buildArgs += "ARGOCD_VERSION=$($BuildEnv['ARGOCD_VERSION'])"
}

Add-BuildArgIfPresent -Name "PIP_INDEX_URL" -Value $PipIndexUrl -EnvName1 "PIP_INDEX_URL" -EnvName2 "N8N_PIP_INDEX_URL"
Add-BuildArgIfPresent -Name "PIP_EXTRA_INDEX_URL" -Value $PipExtraIndexUrl -EnvName1 "PIP_EXTRA_INDEX_URL" -EnvName2 "N8N_PIP_EXTRA_INDEX_URL"
Add-BuildArgIfPresent -Name "PIP_TRUSTED_HOST" -Value $PipTrustedHost -EnvName1 "PIP_TRUSTED_HOST" -EnvName2 "N8N_PIP_TRUSTED_HOST"
Add-BuildArgIfPresent -Name "PIP_DEFAULT_TIMEOUT" -Value $PipDefaultTimeout -EnvName1 "PIP_DEFAULT_TIMEOUT" -EnvName2 "N8N_PIP_DEFAULT_TIMEOUT"

docker build -t $Tag @buildArgs $RootDir

# windows/build.ps1
#
# 作用：构建 n8n-super Docker 镜像（Windows/PowerShell）。
#
# 用法：
#   .\windows\build.ps1
#   .\windows\build.ps1 -Tag "n8n-super:1.78.1"
param(
  [string]$Tag = "n8n-super:1.78.1",
  [string]$CommunityNodes = "",
  [string]$ArgoCdVersion = "",
  [string]$PipIndexUrl = "",
  [string]$PipExtraIndexUrl = "",
  [string]$PipTrustedHost = "",
  [string]$PipDefaultTimeout = ""
)

# 使用仓库根目录作为 build context
$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")

$buildArgs = @()

if ($CommunityNodes) {
  $buildArgs += "--build-arg"
  $buildArgs += "COMMUNITY_NODES=$CommunityNodes"
} elseif ($env:COMMUNITY_NODES) {
  $buildArgs += "--build-arg"
  $buildArgs += "COMMUNITY_NODES=$($env:COMMUNITY_NODES)"
}

if ($ArgoCdVersion) {
  $buildArgs += "--build-arg"
  $buildArgs += "ARGOCD_VERSION=$ArgoCdVersion"
} elseif ($env:ARGOCD_VERSION) {
  $buildArgs += "--build-arg"
  $buildArgs += "ARGOCD_VERSION=$($env:ARGOCD_VERSION)"
}

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
  }
}

Add-BuildArgIfPresent -Name "PIP_INDEX_URL" -Value $PipIndexUrl -EnvName1 "PIP_INDEX_URL" -EnvName2 "N8N_PIP_INDEX_URL"
Add-BuildArgIfPresent -Name "PIP_EXTRA_INDEX_URL" -Value $PipExtraIndexUrl -EnvName1 "PIP_EXTRA_INDEX_URL" -EnvName2 "N8N_PIP_EXTRA_INDEX_URL"
Add-BuildArgIfPresent -Name "PIP_TRUSTED_HOST" -Value $PipTrustedHost -EnvName1 "PIP_TRUSTED_HOST" -EnvName2 "N8N_PIP_TRUSTED_HOST"
Add-BuildArgIfPresent -Name "PIP_DEFAULT_TIMEOUT" -Value $PipDefaultTimeout -EnvName1 "PIP_DEFAULT_TIMEOUT" -EnvName2 "N8N_PIP_DEFAULT_TIMEOUT"

docker build -t $Tag @buildArgs $RootDir

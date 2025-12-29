# windows/build.ps1
#
# 作用：构建 n8n-super Docker 镜像（Windows/PowerShell）。
#
# 用法：
#   .\windows\build.ps1
#   .\windows\build.ps1 -Tag "n8n-super:1.78.1"
param(
  [string]$Tag = "n8n-super:1.78.1"
)

# 使用仓库根目录作为 build context
$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")

docker build -t $Tag $RootDir

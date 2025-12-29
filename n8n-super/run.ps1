param(
  [switch]$Build,
  [switch]$Detached
)

if (-not $PSBoundParameters.ContainsKey('Build')) { $Build = $true }
if (-not $PSBoundParameters.ContainsKey('Detached')) { $Detached = $true }

if ($Build) {
  docker compose -f docker-compose.yml build
}

if ($Detached) {
  docker compose -f docker-compose.yml up -d
} else {
  docker compose -f docker-compose.yml up
}

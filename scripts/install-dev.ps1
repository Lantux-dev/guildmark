<#
.SYNOPSIS
  Enlaza la carpeta del addon con la carpeta AddOns del juego (junction),
  para que los cambios del repo se vean en el juego con un /reload.

.EXAMPLE
  .\scripts\install-dev.ps1
  .\scripts\install-dev.ps1 -WowPath "D:\Games\World of Warcraft" -Flavor _classic_beta_
#>
param(
    [string]$WowPath = "C:\Program Files (x86)\World of Warcraft",
    # _classic_era_ para Classic Era, _classic_beta_ para la beta de Forever.
    [string]$Flavor = "_classic_beta_"
)

$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "..\Guildmark" | Resolve-Path
$flavorPath = Join-Path $WowPath $Flavor

if (-not (Test-Path $flavorPath)) {
    $found = Get-ChildItem $WowPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "_*_" } | Select-Object -ExpandProperty Name
    throw "No existe $flavorPath. Versiones instaladas: $($found -join ', ')"
}

$addons = Join-Path $flavorPath "Interface\AddOns"
New-Item -ItemType Directory -Force $addons | Out-Null
$target = Join-Path $addons "Guildmark"

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -eq "Junction") {
        Write-Host "Ya está enlazado: $target -> $($item.Target)"
        exit 0
    }
    throw "Ya existe una carpeta Guildmark normal en $addons. Bórrala o renómbrala antes de enlazar."
}

New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Enlazado: $target -> $source"
Write-Host "En el juego: activa 'Guildmark' en la lista de addons y usa /gmk."

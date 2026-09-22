<#
  Build the RSSOwl installer: compile -> build the product folder -> package.

  One command for all three steps. The version is read from org.rssowl.ui's
  MANIFEST.MF and handed to Inno Setup, so the version only ever has to be
  bumped in one place: the manifest.

  Examples:
    .\package.ps1
    .\package.ps1 -SkipBuild        # reuse the existing build-out
    .\package.ps1 -SkipDist         # reuse the existing dist folder
#>
[CmdletBinding()]
param(
  [string] $DistDir = (Join-Path $PSScriptRoot "dist"),
  [string] $OutDir  = (Join-Path $PSScriptRoot "build-out"),
  [string] $Iscc    = $null,
  [switch] $SkipBuild,
  [switch] $SkipDist
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

if (-not $Iscc) {
  $Iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc) { Fail "No ISCC.exe from Inno Setup 6 found. Pass -Iscc." }

# The manifest version is <major>.<minor>.<micro>.qualifier; Inno only needs
# the first three numbers, "qualifier" being an OSGi convention.
$bundleVersion = Get-BundleVersion (Join-Path $root "org.rssowl.ui")
$appVersion = ($bundleVersion -split '\.')[0..2] -join '.'

Write-Host "RSSOwl $appVersion (bundle $bundleVersion)"
Write-Host ""

# --- 1. product folder -------------------------------------------------------
if (-not $SkipDist) {
  # Splat with a hashtable: passing an array into the call makes PowerShell
  # treat "-SkipBuild" as a positional value rather than a switch name.
  $distArgs = @{ OutDir = $DistDir }
  if ($SkipBuild) { $distArgs.SkipBuild = $true }

  & (Join-Path $root "dist.ps1") @distArgs
  if ($LASTEXITCODE -ne 0) { Fail "dist.ps1 failed." }
}
if (-not (Test-Path (Join-Path $DistDir "RSSOwl.exe"))) { Fail "No $DistDir\RSSOwl.exe. Run .\dist.ps1 first." }

# --- 2. package --------------------------------------------------------------
Write-Host ""
Write-Host "Packaging with Inno Setup..."
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $Iscc "/DAppVersion=$appVersion" "/DDistDir=$DistDir" "/O$OutDir" (Join-Path $root "rssowl.iss")
if ($LASTEXITCODE -ne 0) { Fail "ISCC failed (code $LASTEXITCODE)." }

$setup = Join-Path $OutDir "RSSOwl-$appVersion-setup.exe"
if (-not (Test-Path $setup)) { Fail "No output at $setup" }

Write-Host ""
Write-Host ("Done: $setup  ({0:N1} MB)" -f ((Get-Item $setup).Length / 1MB)) -ForegroundColor Green

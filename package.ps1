<#
  Dung ban cai dat RSSOwl: bien dich -> dung thu muc san pham -> dong goi.

  Mot lenh duy nhat cho ca ba buoc. Phien ban duoc doc tu MANIFEST.MF cua
  org.rssowl.ui roi truyen sang Inno Setup, nen chi phai nang phien ban o mot
  cho duy nhat la manifest.

  Vi du:
    .\package.ps1
    .\package.ps1 -SkipBuild        # dung lai build-out co san
    .\package.ps1 -SkipDist         # dung lai thu muc dist co san
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

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

if (-not $Iscc) {
  $Iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc) { Fail "Khong thay ISCC.exe cua Inno Setup 6. Truyen -Iscc." }

# Phien ban trong manifest la <major>.<minor>.<micro>.qualifier; Inno chi can
# ba so dau, con "qualifier" la quy uoc cua OSGi.
$bundleVersion = Get-BundleVersion (Join-Path $root "org.rssowl.ui")
$appVersion = ($bundleVersion -split '\.')[0..2] -join '.'

Write-Host "RSSOwl $appVersion (bundle $bundleVersion)"
Write-Host ""

# --- 1. thu muc san pham -----------------------------------------------------
if (-not $SkipDist) {
  # Splat bang hashtable: nhoi mot mang vao loi goi thi PowerShell coi
  # "-SkipBuild" la gia tri vi tri chu khong phai ten switch.
  $distArgs = @{ OutDir = $DistDir }
  if ($SkipBuild) { $distArgs.SkipBuild = $true }

  & (Join-Path $root "dist.ps1") @distArgs
  if ($LASTEXITCODE -ne 0) { Fail "dist.ps1 that bai." }
}
if (-not (Test-Path (Join-Path $DistDir "RSSOwl.exe"))) { Fail "Khong thay $DistDir\RSSOwl.exe. Chay .\dist.ps1 truoc." }

# --- 2. dong goi -------------------------------------------------------------
Write-Host ""
Write-Host "Dong goi bang Inno Setup..."
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $Iscc "/DAppVersion=$appVersion" "/DDistDir=$DistDir" "/O$OutDir" (Join-Path $root "rssowl.iss")
if ($LASTEXITCODE -ne 0) { Fail "ISCC that bai (ma $LASTEXITCODE)." }

$setup = Join-Path $OutDir "RSSOwl-$appVersion-setup.exe"
if (-not (Test-Path $setup)) { Fail "Khong thay ket qua tai $setup" }

Write-Host ""
Write-Host ("Xong: $setup  ({0:N1} MB)" -f ((Get-Item $setup).Length / 1MB)) -ForegroundColor Green

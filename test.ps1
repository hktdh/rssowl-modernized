<#
  Chay test cua RSSOwl trong runtime that, khong can mo IDE.

  Vi sao phai the: cac test trong org.rssowl.core.tests la plug-in test - chung
  goi Owl.getModelFactory() va tang persistence, nen chi co nghia khi OSGi da
  chay. PDE chay duoc chung nhung dieu khien tu IDE qua socket, khong dung tu
  script duoc. Bundle test vi the mang mot application headless tu goi JUnit
  (xem HeadlessTestApplication).

  Moi lan chay dung mot data dir moi tinh roi xoa di: test ghi thang vao
  database that, khong duoc dung chung voi profile dang dung de thu tay.

  Vi du:
    .\test.ps1                                     # chay bo test UI
    .\test.ps1 -Classes org.rssowl.core.tests.ui.NewsGroupFilterTest
    .\test.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
  [string]   $RuntimeHome = "D:\CDS\tools\rssowl-run-4x",
  [string]   $JavaHome    = $null,
  [string[]] $Classes     = @("org.rssowl.core.tests.ui.NewsVisibleElementsTest"),
  [string]   $DataDir     = $null,
  [switch]   $SkipBuild,
  [switch]   $KeepData
)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$build = Join-Path $root "build-out"

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { Fail "Khong thay JDK 21." }
if (-not (Test-Path (Join-Path $RuntimeHome "plugins"))) { Fail "Khong thay runtime tai $RuntimeHome" }

# --- 1. bien dich ------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -IncludeTests
  if ($LASTEXITCODE -ne 0) { Fail "Bien dich that bai." }
}
if (-not (Test-Path (Join-Path $build "tests"))) { Fail "Chua co build-out\tests. Chay .\build.ps1 -IncludeTests" }

# --- 2. dat bundle cua RSSOwl va bundle test ---------------------------------
$plugins = Join-Path $RuntimeHome "plugins"
Copy-RssOwlBundles $root (Join-Path $build "main") $plugins

$src  = Join-Path $root "org.rssowl.core.tests"
$dest = Join-Path $plugins "org.rssowl.core.tests_$(Get-BundleVersion $src)"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

Copy-Tree (Join-Path $src "META-INF") (Join-Path $dest "META-INF")
foreach ($f in @("plugin.xml", "plugin.properties", "about.html")) {
  $p = Join-Path $src $f
  if (Test-Path $p) { Copy-Item $p $dest -Force }
}

# data/ chua feed mau ma nhieu test doc toi
Copy-Tree (Join-Path $src "data") (Join-Path $dest "data")
Copy-Tree (Join-Path $build "tests\org\rssowl\core\tests") (Join-Path $dest "org\rssowl\core\tests")

# Resource nam lan trong src giong hai bundle kia.
Copy-Tree (Join-Path $src "src") $dest @("*.java")

Write-Host ("  {0,-24} {1} class" -f "org.rssowl.core.tests", @(Get-ChildItem $dest -Recurse -Filter *.class).Count)

# --- 3. bundles.info ---------------------------------------------------------
$bundlesInfo = Join-Path $RuntimeHome "configuration\org.eclipse.equinox.simpleconfigurator\bundles.info"
if (-not (Test-Path $bundlesInfo)) { Fail "Khong thay bundles.info trong $RuntimeHome" }
Write-BundlesInfo $plugins $bundlesInfo $bundlesInfo (Get-StartLevels $bundlesInfo)

# --- 4. chay -----------------------------------------------------------------
$temporary = -not $DataDir
if ($temporary) { $DataDir = Join-Path ([IO.Path]::GetTempPath()) ("rssowl-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

Write-Host ""
Write-Host "Chay test (data: $DataDir)"
foreach ($c in $Classes) { Write-Host "  $c" }
Write-Host ""

$launcher = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.launcher_*.jar" | Select-Object -First 1).FullName
$java = Join-Path $JavaHome "bin\java.exe"

# Chay thang qua launcher jar thay vi eclipsec.exe de bat duoc ma thoat.
$a = @(
  "-Xmx512m",
  "--add-opens=java.base/java.lang=ALL-UNNAMED",
  "--add-opens=java.base/java.util=ALL-UNNAMED",
  "--add-opens=java.base/java.io=ALL-UNNAMED",
  "-jar", $launcher,
  "-application", "org.rssowl.core.tests.headless",
  "-data", $DataDir,
  "-consolelog"
) + $Classes

# Goi qua cmd /c: PS 5.1 boc stderr cua native exe thanh ErrorRecord, va JUnit
# cung nhu Equinox deu ghi mot phan ra stderr.
$quoted = ($a | ForEach-Object { '"' + $_ + '"' }) -join " "
cmd /c "`"$java`" $quoted 2>&1"
$code = $LASTEXITCODE

if ($temporary -and -not $KeepData) { Remove-Item $DataDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($code -eq 0) { Write-Host "Test dat" -ForegroundColor Green } else { Write-Host "Test that bai (ma $code)" -ForegroundColor Red }
exit $code

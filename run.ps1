<#
  Deploy RSSOwl 2.3 thanh mot Eclipse RCP runtime doc lap roi chay.

  Cach hoat dong: chep bundle vao plugins/ roi ghi ten chung vao bundles.info,
  danh sach ma org.eclipse.equinox.simpleconfigurator doc luc khoi dong. Day la
  co che cua Eclipse 4.x; xem phan 4 ben duoi de biet vi sao khong dung
  org.eclipse.update.configurator cua dong 3.x nua.

  Runtime la ban sao rieng cua Eclipse SDK (-RuntimeHome), khong dung vao ban SDK
  dung lam target platform, de IDE va app chay doc lap nhau.

  Vi du:
    .\run.ps1                  # build, deploy, chay
    .\run.ps1 -SkipBuild       # deploy lai va chay, bo qua buoc bien dich
    .\run.ps1 -DeployOnly      # chi deploy, khong chay
#>
[CmdletBinding()]
param(
  [string] $RuntimeHome = "D:\CDS\tools\rssowl-run-4x",
  [string] $JavaHome    = $env:JAVA_HOME,
  [string] $DataDir     = "D:\CDS\build\rssowl-data",
  [switch] $SkipBuild,
  [switch] $DeployOnly
)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$build = Join-Path $root "build-out\main"

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

# Phan dat bundle dung chung voi dist.ps1, de ban phat hanh giong het ban da
# kiem thu o day.
. (Join-Path $PSScriptRoot "build-common.ps1")

# Ghim JDK theo runtime, khong tin JAVA_HOME (trinh cai JDK ghi de bien nay).
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { $JavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") }
if (-not $JavaHome) { Fail "Khong xac dinh duoc JAVA_HOME." }
$JavaHome = $JavaHome.TrimEnd('\')
if (-not (Test-Path (Join-Path $RuntimeHome "plugins"))) { Fail "Khong thay runtime tai $RuntimeHome" }

# --- 1. bien dich ------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -Clean
  if ($LASTEXITCODE -ne 0) { Fail "Bien dich that bai." }
}
if (-not (Test-Path $build)) { Fail "Khong thay $build. Chay .\build.ps1 truoc." }

$plugins = Join-Path $RuntimeHome "plugins"

# --- 2. dat sau bundle cua RSSOwl ---------------------------------------------
Copy-RssOwlBundles $root $build $plugins

# --- 3. config.ini -----------------------------------------------------------
$osgi = (Get-ChildItem $plugins -Filter "org.eclipse.osgi_*.jar" |
         Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1).Name
if (-not $osgi) { Fail "Khong thay bundle org.eclipse.osgi trong $plugins" }

$cfgDir = Join-Path $RuntimeHome "configuration"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

# Eclipse 4.x dung p2/simpleconfigurator, khong dung org.eclipse.update.configurator
# nua. Co gang khoi dong bang configurator cu tren ban 4.41 thi core.runtime khong
# resolve duoc (thieu core.jobs) va app chet ngay luc khoi dong. Cach dung la them
# bundle cua minh vao bundles.info, la danh sach ma simpleconfigurator doc.
$bundlesInfo = Join-Path $cfgDir "org.eclipse.equinox.simpleconfigurator\bundles.info"
if (-not (Test-Path $bundlesInfo)) { Fail "Khong thay bundles.info. Runtime nay khong phai ban p2?" }

# Giu nguyen cac dong cua ban Eclipse, chi thay phan org.rssowl.*
Write-BundlesInfo $plugins $bundlesInfo $bundlesInfo (Get-StartLevels $bundlesInfo)

$simple = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.simpleconfigurator_*.jar" |
           Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1).Name
if (-not $simple) { Fail "Khong thay bundle simpleconfigurator trong $plugins" }

@(
  "osgi.framework=file\:plugins/$osgi"
  "osgi.bundles=reference\:file\:$simple@1\:start"
  "org.eclipse.equinox.simpleconfigurator.configUrl=file\:org.eclipse.equinox.simpleconfigurator/bundles.info"
  "osgi.bundles.defaultStartLevel=4"
  "eclipse.product=org.rssowl.ui.product"
  "eclipse.application=org.rssowl.ui.rssowl"
  "osgi.splashPath=platform\:/base/plugins/org.rssowl.ui"
) -join "`r`n" | Set-Content (Join-Path $cfgDir "config.ini") -Encoding ASCII

@(
  "-startup"
  (Get-ChildItem $plugins -Filter "org.eclipse.equinox.launcher_*.jar" | Select-Object -First 1 |
     ForEach-Object { "plugins/$($_.Name)" })
  "--launcher.library"
  # Delta pack mang ca hai bien the x86 va x86_64; phai khop kien truc cua JVM,
  # lay nham 32-bit thi launcher bao "Java was started but returned exit code 13".
  (Get-ChildItem $plugins -Directory -Filter "org.eclipse.equinox.launcher.win32.win32.x86_64_*" |
     Select-Object -First 1 | ForEach-Object { "plugins/$($_.Name)" })
  "-vm"
  "$JavaHome\bin\javaw.exe"
  "-vmargs"
  "-Xms40m"
  "-Xmx512m"   # 192m cua rssowl.product la dinh muc doi 2011, Eclipse 4.x nang hon
  # db4o 6.1 reflect vao field noi bo cua java.lang.Enum de luu enum. Tu JDK 16
  # strong encapsulation chan viec do, nem InaccessibleObjectException ngay khi
  # doc preferences luc khoi dong. Phai mo dung cac package db4o cham toi.
  "--add-opens=java.base/java.lang=ALL-UNNAMED"
  "--add-opens=java.base/java.util=ALL-UNNAMED"
  "--add-opens=java.base/java.io=ALL-UNNAMED"
) -join "`r`n" | Set-Content (Join-Path $RuntimeHome "eclipse.ini") -Encoding ASCII

Write-Host "Deploy xong vao $RuntimeHome" -ForegroundColor Green
if ($DeployOnly) { exit 0 }

# --- 4. chay -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Write-Host "Dang chay RSSOwl (data: $DataDir)..."
Start-Process -FilePath (Join-Path $RuntimeHome "eclipse.exe") `
  -ArgumentList "-data", $DataDir, "-clean", "-consolelog" | Out-Null

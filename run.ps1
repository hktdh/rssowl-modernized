<#
  Deploy RSSOwl 2.3 as a standalone Eclipse RCP runtime and launch it.

  How it works: copy the bundles into plugins/, then write their names into
  bundles.info, the list org.eclipse.equinox.simpleconfigurator reads at
  startup. That is the Eclipse 4.x mechanism; see section 4 below for why
  org.eclipse.update.configurator from the 3.x line is no longer used.

  The runtime is a separate copy of the Eclipse SDK (-RuntimeHome), not the SDK
  used as the target platform, so the IDE and the app stay independent.

  Examples:
    .\run.ps1                  # build, deploy, launch
    .\run.ps1 -SkipBuild       # redeploy and launch, skipping compilation
    .\run.ps1 -DeployOnly      # deploy only, do not launch
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

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# The bundle layout is shared with dist.ps1, so the release is identical to
# what was tested here.
. (Join-Path $PSScriptRoot "build-common.ps1")

# Pin the JDK to the runtime, do not trust JAVA_HOME (JDK installers overwrite
# that variable).
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { $JavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") }
if (-not $JavaHome) { Fail "Could not determine JAVA_HOME." }
$JavaHome = $JavaHome.TrimEnd('\')
if (-not (Test-Path (Join-Path $RuntimeHome "plugins"))) { Fail "No runtime at $RuntimeHome" }

# --- 1. compile --------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -Clean
  if ($LASTEXITCODE -ne 0) { Fail "Compilation failed." }
}
if (-not (Test-Path $build)) { Fail "No $build. Run .\build.ps1 first." }

$plugins = Join-Path $RuntimeHome "plugins"

# --- 2. lay down RSSOwl's bundles --------------------------------------------
Copy-RssOwlBundles $root $build $plugins

# --- 3. config.ini -----------------------------------------------------------
$osgi = (Get-ChildItem $plugins -Filter "org.eclipse.osgi_*.jar" |
         Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1).Name
if (-not $osgi) { Fail "No org.eclipse.osgi bundle in $plugins" }

$cfgDir = Join-Path $RuntimeHome "configuration"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

# Eclipse 4.x uses p2/simpleconfigurator, no longer org.eclipse.update.configurator.
# Trying to boot 4.41 with the old configurator leaves core.runtime unresolved
# (core.jobs is missing) and the app dies at startup. The right way is to add
# our bundles to bundles.info, the list simpleconfigurator reads.
$bundlesInfo = Join-Path $cfgDir "org.eclipse.equinox.simpleconfigurator\bundles.info"
if (-not (Test-Path $bundlesInfo)) { Fail "No bundles.info. Is this runtime not a p2 install?" }

# Keep Eclipse's own lines, replace only the org.rssowl.* part.
Write-BundlesInfo $plugins $bundlesInfo $bundlesInfo (Get-StartLevels $bundlesInfo)

$simple = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.simpleconfigurator_*.jar" |
           Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1).Name
if (-not $simple) { Fail "No simpleconfigurator bundle in $plugins" }

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
  # The delta pack carries both the x86 and the x86_64 variant; it has to match
  # the JVM's architecture. Picking the 32-bit one makes the launcher report
  # "Java was started but returned exit code 13".
  (Get-ChildItem $plugins -Directory -Filter "org.eclipse.equinox.launcher.win32.win32.x86_64_*" |
     Select-Object -First 1 | ForEach-Object { "plugins/$($_.Name)" })
  "-vm"
  "$JavaHome\bin\javaw.exe"
  "-vmargs"
  "-Xms40m"
  "-Xmx512m"   # the 192m in rssowl.product is a 2011 figure; Eclipse 4.x needs more
  # db4o 6.1 reflects into internal fields of java.lang.Enum to store enums. As
  # of JDK 16 strong encapsulation blocks that, throwing
  # InaccessibleObjectException as soon as preferences are read at startup. The
  # packages db4o reaches into have to be opened.
  "--add-opens=java.base/java.lang=ALL-UNNAMED"
  "--add-opens=java.base/java.util=ALL-UNNAMED"
  "--add-opens=java.base/java.io=ALL-UNNAMED"
) -join "`r`n" | Set-Content (Join-Path $RuntimeHome "eclipse.ini") -Encoding ASCII

Write-Host "Deployed to $RuntimeHome" -ForegroundColor Green
if ($DeployOnly) { exit 0 }

# --- 4. launch ---------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Write-Host "Launching RSSOwl (data: $DataDir)..."
Start-Process -FilePath (Join-Path $RuntimeHome "eclipse.exe") `
  -ArgumentList "-data", $DataDir, "-clean", "-consolelog" | Out-Null

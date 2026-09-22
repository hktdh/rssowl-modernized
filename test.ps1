<#
  Run RSSOwl's tests in a real runtime, without opening the IDE.

  Why it has to work this way: the tests in org.rssowl.core.tests are plug-in
  tests - they call Owl.getModelFactory() and the persistence layer, so they
  only mean anything once OSGi is running. PDE can run them, but it drives them
  from the IDE over a socket, which is not usable from a script. The test
  bundle therefore carries a headless application that invokes JUnit itself
  (see HeadlessTestApplication).

  Every run uses a brand new data dir and then deletes it: the tests write
  straight into a real database, and must not share the profile being used for
  manual testing.

  Examples:
    .\test.ps1                                     # run the UI test suite
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

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { Fail "No JDK 21 found." }
if (-not (Test-Path (Join-Path $RuntimeHome "plugins"))) { Fail "No runtime at $RuntimeHome" }

# --- 1. compile --------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -IncludeTests
  if ($LASTEXITCODE -ne 0) { Fail "Compilation failed." }
}
if (-not (Test-Path (Join-Path $build "tests"))) { Fail "No build-out\tests yet. Run .\build.ps1 -IncludeTests" }

# --- 2. lay down RSSOwl's bundles and the test bundle ------------------------
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

# data/ holds the sample feeds a number of tests read
Copy-Tree (Join-Path $src "data") (Join-Path $dest "data")
Copy-Tree (Join-Path $build "tests\org\rssowl\core\tests") (Join-Path $dest "org\rssowl\core\tests")

# Resources live among the sources, same as in the other two bundles.
Copy-Tree (Join-Path $src "src") $dest @("*.java")

Write-Host ("  {0,-24} {1} classes" -f "org.rssowl.core.tests", @(Get-ChildItem $dest -Recurse -Filter *.class).Count)

# --- 3. bundles.info ---------------------------------------------------------
$bundlesInfo = Join-Path $RuntimeHome "configuration\org.eclipse.equinox.simpleconfigurator\bundles.info"
if (-not (Test-Path $bundlesInfo)) { Fail "No bundles.info in $RuntimeHome" }
Write-BundlesInfo $plugins $bundlesInfo $bundlesInfo (Get-StartLevels $bundlesInfo)

# --- 4. run ------------------------------------------------------------------
$temporary = -not $DataDir
if ($temporary) { $DataDir = Join-Path ([IO.Path]::GetTempPath()) ("rssowl-test-" + [Guid]::NewGuid().ToString("N").Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

Write-Host ""
Write-Host "Running tests (data: $DataDir)"
foreach ($c in $Classes) { Write-Host "  $c" }
Write-Host ""

$launcher = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.launcher_*.jar" | Select-Object -First 1).FullName
$java = Join-Path $JavaHome "bin\java.exe"

# Go straight through the launcher jar rather than eclipsec.exe, so the exit
# code can be captured.
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

# Call through cmd /c: PS 5.1 wraps a native exe's stderr into ErrorRecords,
# and both JUnit and Equinox write part of their output to stderr.
$quoted = ($a | ForEach-Object { '"' + $_ + '"' }) -join " "
cmd /c "`"$java`" $quoted 2>&1"
$code = $LASTEXITCODE

if ($temporary -and -not $KeepData) { Remove-Item $DataDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
if ($code -eq 0) { Write-Host "Tests passed" -ForegroundColor Green } else { Write-Host "Tests failed (code $code)" -ForegroundColor Red }
exit $code

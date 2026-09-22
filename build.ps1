<#
  Compile RSSOwl 2.3 with Eclipse's ecj, without opening the IDE.

  Why ecj and not javac: ecj is the compiler PDE uses, so the result matches
  an in-IDE build - same error/warning configuration, same way of reading
  MANIFEST.MF.

  Builds against Eclipse 4.41 + JDK 21.
  The Update Manager subsystem has been removed, so there is no dependency on
  org.eclipse.update.* left (those bundles are gone from Eclipse 4.x).
  Code on this branch can NO LONGER be compiled against 3.8.2: it uses the
  generic form of getAdapter(Class<T>), which only exists from Eclipse 4.x on.

  This script used to strip org.apache.lucene* from the classpath, because
  RSSOwl carried its own Lucene 2.3.2 which clashed with Eclipse's copy. Now
  org.rssowl.core uses the target platform's Lucene directly, so there is no
  clash and nothing to strip.

  Examples:
    .\build.ps1
    .\build.ps1 -IncludeTests
    .\build.ps1 -EclipseHome "C:\eclipse" -Clean
#>
[CmdletBinding()]
param(
  [string] $EclipseHome = "D:\CDS\tools\eclipse441\eclipse",
  [string] $JavaHome    = $env:JAVA_HOME,
  [string] $OutDir      = (Join-Path $PSScriptRoot "build-out"),
  [string] $Compliance  = "21",
  [switch] $IncludeTests,
  [switch] $Clean
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- environment check -------------------------------------------------------
# Pin the JDK to the target platform instead of trusting JAVA_HOME: every JDK
# installer overwrites the machine-level JAVA_HOME, so it is not reliable.
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { $JavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") }
if (-not $JavaHome) { Fail "No JAVA_HOME. Pass -JavaHome or set the environment variable." }
$JavaHome = $JavaHome.TrimEnd('\')
$java = Join-Path $JavaHome "bin\java.exe"
if (-not (Test-Path $java)) { Fail "No java.exe at $java" }
if (-not (Test-Path (Join-Path $EclipseHome "plugins"))) { Fail "No target platform at $EclipseHome" }

# As of Eclipse 4.x, ecj was split out of org.eclipse.jdt.core into its own
# bundle. Look for the split-out one first, then fall back to the 3.x name.
$ecj = Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter "org.eclipse.jdt.core.compiler.batch_*.jar" |
       Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
if (-not $ecj) {
  $ecj = Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter "org.eclipse.jdt.core_*.jar" |
         Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
}
if (-not $ecj) { Fail "No ecj bundle found in $EclipseHome\plugins" }

if ($Clean -and (Test-Path $OutDir)) { Remove-Item $OutDir -Recurse -Force }

# --- classpath ---------------------------------------------------------------
$cp = @(
  "org.rssowl.lib.db4o", "org.rssowl.lib.httpclient", "org.rssowl.lib.jdom"
) | ForEach-Object { Join-Path $root $_ }

# The query parser is the one Lucene piece the target platform does not ship,
# so it is wrapped as a bundle here and stays a jar on its Bundle-ClassPath.
$cp += Get-ChildItem (Join-Path $root "org.rssowl.lib.lucene.queryparser") -Filter *.jar |
       ForEach-Object { $_.FullName }

$cp += Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter *.jar |
       Where-Object { $_.Name -notlike "*.source_*" } |
       ForEach-Object { $_.FullName }

# Some bundles are directories holding nested jars rather than a single jar.
$cp += Get-ChildItem (Join-Path $EclipseHome "plugins") -Directory |
       ForEach-Object { Get-ChildItem $_.FullName -Filter *.jar -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.FullName } }

# --- one compiler pass -------------------------------------------------------
function Invoke-Ecj([string] $label, [string[]] $sources, [string] $dest, [string[]] $extraCp) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $argfile = Join-Path $env:TEMP "ecj-$label.args"
  $logfile = Join-Path $OutDir  "$label.log"

  $a = @("-$Compliance", "-nowarn", "-proc:none", "-encoding", "UTF-8",
         "-d", $dest, "-classpath", (($extraCp + $cp) -join ";")) + $sources

  # UTF8Encoding($false): Set-Content -Encoding utf8 on PS 5.1 adds a BOM, and
  # ecj reads the BOM as part of the first argument and reports
  # "Unrecognized option".
  [IO.File]::WriteAllText($argfile, (($a | ForEach-Object { '"' + $_ + '"' }) -join "`r`n"),
                          (New-Object Text.UTF8Encoding $false))

  # Call through cmd /c: PS 5.1 wraps a native exe's stderr into ErrorRecords.
  cmd /c "`"$java`" -cp `"$($ecj.FullName)`" org.eclipse.jdt.internal.compiler.batch.Main `"@$argfile`" > `"$logfile`" 2>&1"

  $errs    = @(Select-String -Path $logfile -Pattern '^\d+\. ERROR' -ErrorAction SilentlyContinue)
  $classes = @(Get-ChildItem $dest -Recurse -Filter *.class -ErrorAction SilentlyContinue).Count

  if ($errs.Count -gt 0) {
    Write-Host ("  {0,-12} {1} error(s)" -f $label, $errs.Count) -ForegroundColor Red
    Get-Content $logfile | Select-Object -Last 40 | ForEach-Object { "    $_" }
    return $false
  }
  Write-Host ("  {0,-12} OK, {1} classes" -f $label, $classes) -ForegroundColor Green
  return $true
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host "RSSOwl 2.3 | JDK $JavaHome | target $EclipseHome | compliance $Compliance"

$main = Join-Path $OutDir "main"
$ok = Invoke-Ecj "core+ui" @((Join-Path $root "org.rssowl.core\src"), (Join-Path $root "org.rssowl.ui\src")) $main @()
if (-not $ok) { exit 1 }

if ($IncludeTests) {
  $ok = Invoke-Ecj "core.tests" @((Join-Path $root "org.rssowl.core.tests\src")) (Join-Path $OutDir "tests") @($main)
  if (-not $ok) { exit 1 }
}

Write-Host "Done. Output in $OutDir" -ForegroundColor Green

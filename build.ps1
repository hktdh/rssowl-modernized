<#
  Bien dich RSSOwl 2.1 bang ecj cua Eclipse, khong can mo IDE.

  Vi sao dung ecj chu khong dung javac: manifest khai compliance J2SE-1.5,
  va ecj ho tro muc nay trong khi javac doi moi da bo. ecj cung la trinh
  bien dich ma PDE dung, nen ket qua khop voi build trong IDE.

  NHANH NAY (migrate-eclipse-4x) build tren Eclipse 4.41 + JDK 21.
  Subsystem Update Manager da duoc go bo, nen khong con rang buoc vao
  org.eclipse.update.* (cac bundle do da bien mat khoi Eclipse 4.x).
  Code o nhanh nay KHONG con bien dich duoc tren 3.8.2: no dung
  getAdapter(Class<T>) dang generic, chi co tu Eclipse 4.x.

  Truoc day phai loai org.apache.lucene* khoi classpath vi RSSOwl mang theo
  Lucene 2.3.2 rieng va no dung do voi ban Lucene cua Eclipse. Gio org.rssowl.core
  dung thang Lucene cua target platform nen khong con xung dot, khong con loai tru.

  Vi du:
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

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

# --- kiem tra moi truong -----------------------------------------------------
# Ghim JDK theo target platform thay vi tin JAVA_HOME: moi lan cai them mot JDK
# la trinh cai ghi de JAVA_HOME cap May, nen no khong dang tin.
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { $JavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") }
if (-not $JavaHome) { Fail "Chua co JAVA_HOME. Truyen -JavaHome hoac dat bien moi truong." }
$JavaHome = $JavaHome.TrimEnd('\')
$java = Join-Path $JavaHome "bin\java.exe"
if (-not (Test-Path $java)) { Fail "Khong thay java.exe tai $java" }
if (-not (Test-Path (Join-Path $EclipseHome "plugins"))) { Fail "Khong thay target platform tai $EclipseHome" }

# Tu Eclipse 4.x, ecj tach khoi org.eclipse.jdt.core sang bundle rieng.
# Tim ban tach truoc, roi moi lui ve ten cu cua dong 3.x.
$ecj = Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter "org.eclipse.jdt.core.compiler.batch_*.jar" |
       Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
if (-not $ecj) {
  $ecj = Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter "org.eclipse.jdt.core_*.jar" |
         Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
}
if (-not $ecj) { Fail "Khong thay bundle ecj trong $EclipseHome\plugins" }

if ($Clean -and (Test-Path $OutDir)) { Remove-Item $OutDir -Recurse -Force }

# --- classpath ---------------------------------------------------------------
$cp = @(
  "org.rssowl.lib.db4o", "org.rssowl.lib.httpclient", "org.rssowl.lib.jdom"
) | ForEach-Object { Join-Path $root $_ }

$cp += Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter *.jar |
       Where-Object { $_.Name -notlike "*.source_*" } |
       ForEach-Object { $_.FullName }

# Vai bundle (vd org.junit4) la thu muc chua jar long nhau.
$cp += Get-ChildItem (Join-Path $EclipseHome "plugins") -Directory |
       ForEach-Object { Get-ChildItem $_.FullName -Filter *.jar -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.FullName } }

# --- chay mot luot bien dich -------------------------------------------------
function Invoke-Ecj([string] $label, [string[]] $sources, [string] $dest, [string[]] $extraCp) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $argfile = Join-Path $env:TEMP "ecj-$label.args"
  $logfile = Join-Path $OutDir  "$label.log"

  $a = @("-$Compliance", "-nowarn", "-proc:none", "-encoding", "UTF-8",
         "-d", $dest, "-classpath", (($extraCp + $cp) -join ";")) + $sources

  # UTF8Encoding($false): Set-Content -Encoding utf8 cua PS 5.1 them BOM,
  # ecj doc BOM thanh mot phan cua tham so dau tien roi bao "Unrecognized option".
  [IO.File]::WriteAllText($argfile, (($a | ForEach-Object { '"' + $_ + '"' }) -join "`r`n"),
                          (New-Object Text.UTF8Encoding $false))

  # Goi qua cmd /c: PS 5.1 boc stderr cua native exe thanh ErrorRecord.
  cmd /c "`"$java`" -cp `"$($ecj.FullName)`" org.eclipse.jdt.internal.compiler.batch.Main `"@$argfile`" > `"$logfile`" 2>&1"

  $errs    = @(Select-String -Path $logfile -Pattern '^\d+\. ERROR' -ErrorAction SilentlyContinue)
  $classes = @(Get-ChildItem $dest -Recurse -Filter *.class -ErrorAction SilentlyContinue).Count

  if ($errs.Count -gt 0) {
    Write-Host ("  {0,-12} {1} loi" -f $label, $errs.Count) -ForegroundColor Red
    Get-Content $logfile | Select-Object -Last 40 | ForEach-Object { "    $_" }
    return $false
  }
  Write-Host ("  {0,-12} OK, {1} class" -f $label, $classes) -ForegroundColor Green
  return $true
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host "RSSOwl 2.1 | JDK $JavaHome | target $EclipseHome | compliance $Compliance"

$main = Join-Path $OutDir "main"
$ok = Invoke-Ecj "core+ui" @((Join-Path $root "org.rssowl.core\src"), (Join-Path $root "org.rssowl.ui\src")) $main @()
if (-not $ok) { exit 1 }

if ($IncludeTests) {
  $ok = Invoke-Ecj "core.tests" @((Join-Path $root "org.rssowl.core.tests\src")) (Join-Path $OutDir "tests") @($main)
  if (-not $ok) { exit 1 }
}

Write-Host "Xong. Ket qua trong $OutDir" -ForegroundColor Green

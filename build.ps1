<#
  Bien dich RSSOwl 2.1 bang ecj cua Eclipse, khong can mo IDE.

  Vi sao dung ecj chu khong dung javac: manifest khai compliance J2SE-1.5,
  va ecj ho tro muc nay trong khi javac doi moi da bo. ecj cung la trinh
  bien dich ma PDE dung, nen ket qua khop voi build trong IDE.

  Vi sao target platform phai la Eclipse 3.x (dang dung 3.8.2, ban 3.x cuoi):
  org.rssowl.ui dung API Update Manager cu, ke ca class internal nhu
  InstallWizard2 va ConfigurationManagerWindow. Bundle org.eclipse.update.*
  da bi go khoi cac dong Eclipse 4.x, nen khong the nang target platform.

  Vi sao loai org.apache.lucene* khoi classpath: Eclipse ship san Lucene 2.9.1
  cho Help search, con RSSOwl can 2.3.2 cua rieng no (org.rssowl.lib.lucene).
  Trong OSGi that thi Require-Bundle tach bach hai cai; o classpath phang
  thi phai loai thu cong, neu khong se dung nham 2.9.1 va gay loi bien dich.

  Vi du:
    .\build.ps1
    .\build.ps1 -IncludeTests
    .\build.ps1 -EclipseHome "C:\eclipse" -Clean
#>
[CmdletBinding()]
param(
  [string] $EclipseHome = "D:\CDS\tools\eclipse",
  [string] $JavaHome    = $env:JAVA_HOME,
  [string] $OutDir      = (Join-Path $PSScriptRoot "build-out"),
  [string] $Compliance  = "1.5",
  [switch] $IncludeTests,
  [switch] $Clean
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

# --- kiem tra moi truong -----------------------------------------------------
# Phai chay tren JDK 8, KHONG lay JAVA_HOME. ecj cua Eclipse 3.8 co truoc Java 9
# nen khong doc duoc module system (jrt://); chay no bang JDK 9+ thi no khong tim
# thay bootclasspath va bao hang nghin loi kieu "java.lang.Object cannot be resolved".
# Cai them mot JDK moi thuong ghi de JAVA_HOME cap May, nen JAVA_HOME khong dang tin.
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-8*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { $JavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine") }
if (-not $JavaHome) { Fail "Chua co JAVA_HOME. Truyen -JavaHome hoac dat bien moi truong." }
$JavaHome = $JavaHome.TrimEnd('\')
$java = Join-Path $JavaHome "bin\java.exe"
if (-not (Test-Path $java)) { Fail "Khong thay java.exe tai $java" }
if (-not (Test-Path (Join-Path $EclipseHome "plugins"))) { Fail "Khong thay target platform tai $EclipseHome" }

$ecj = Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter "org.eclipse.jdt.core_*.jar" |
       Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
if (-not $ecj) { Fail "Khong thay org.eclipse.jdt.core_*.jar trong $EclipseHome\plugins" }

if ($Clean -and (Test-Path $OutDir)) { Remove-Item $OutDir -Recurse -Force }

# --- classpath ---------------------------------------------------------------
# Thu vien cua RSSOwl phai dung TRUOC de thang Lucene 2.9.1 cua Eclipse.
$cp = @(
  "org.rssowl.lib.db4o", "org.rssowl.lib.httpclient",
  "org.rssowl.lib.jdom", "org.rssowl.lib.lucene"
) | ForEach-Object { Join-Path $root $_ }

$cp += Get-ChildItem (Join-Path $EclipseHome "plugins") -Filter *.jar |
       Where-Object { $_.Name -notlike "*.source_*" -and $_.Name -notlike "org.apache.lucene*" } |
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

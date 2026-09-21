<#
  Dung thu muc san pham RSSOwl hoan chinh de dong goi bang Inno Setup.

  Khac run.ps1 o cho nao: run.ps1 dat bundle cua RSSOwl vao mot ban sao Eclipse
  SDK day du (332 MB, 696 bundle) - tien cho viec phat trien nhung khong phai
  thu de phat hanh. Script nay chi lay dung nhung bundle ma RSSOwl can, tinh
  bang bao dong Require-Bundle / Import-Package / Require-Capability, con
  khoang 84 bundle / 42 MB.

  Ban ra cung mang theo mot JRE rut gon bang jlink, nen may dich khong can cai
  Java. Danh sach module o duoi da duoc kiem chung bang cach cho app chay that,
  khong phai suy ra tu tai lieu - xem chu thich cho jdk.management.

  Vi du:
    .\dist.ps1
    .\dist.ps1 -SkipBuild
    .\dist.ps1 -OutDir "D:\CDS\build\rssowl-dist"
#>
[CmdletBinding()]
param(
  [string] $EclipseHome = "D:\CDS\tools\eclipse441\eclipse",
  [string] $JavaHome    = $null,
  [string] $OutDir      = (Join-Path $PSScriptRoot "dist"),
  [switch] $SkipBuild
)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$build = Join-Path $root "build-out\main"

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

# --- 0. moi truong -----------------------------------------------------------
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\jlink.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { Fail "Khong thay JDK 21 co jlink. Truyen -JavaHome." }
$JavaHome = $JavaHome.TrimEnd('\')
if (-not (Test-Path (Join-Path $JavaHome "bin\jlink.exe"))) { Fail "Khong thay jlink trong $JavaHome" }
if (-not (Test-Path (Join-Path $EclipseHome "plugins"))) { Fail "Khong thay target platform tai $EclipseHome" }

$srcPlugins = Join-Path $EclipseHome "plugins"
$version = Get-BundleVersion (Join-Path $root "org.rssowl.ui")

Write-Host "RSSOwl $version | JDK $JavaHome | target $EclipseHome"
Write-Host ""

# --- 1. bien dich ------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -Clean
  if ($LASTEXITCODE -ne 0) { Fail "Bien dich that bai." }
}
if (-not (Test-Path $build)) { Fail "Khong thay $build. Chay .\build.ps1 truoc." }

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
$plugins = Join-Path $OutDir "plugins"
New-Item -ItemType Directory -Force -Path $plugins | Out-Null

# --- 2. bundle cua RSSOwl ----------------------------------------------------
Write-Host "Bundle cua RSSOwl:"
Copy-RssOwlBundles $root $build $plugins

# --- 3. bao dong bundle cua nen tang -----------------------------------------
<#
  Doc header OSGi tu mot bundle, du no la thu muc hay jar.
  Dong tiep trong MANIFEST.MF bat dau bang dung mot dau cach, phai noi lai
  truoc khi tach header, neu khong mot Require-Bundle dai se bi cat cut.
#>
function Read-BundleHeaders([string] $path) {
  $text = $null
  try {
    if (Test-Path $path -PathType Container) {
      $mf = Join-Path $path "META-INF\MANIFEST.MF"
      if (-not (Test-Path $mf)) { return $null }
      $text = [IO.File]::ReadAllText($mf)
    } elseif ($path -like "*.jar") {
      $zip = [IO.Compression.ZipFile]::OpenRead($path)
      try {
        $entry = $zip.GetEntry("META-INF/MANIFEST.MF")
        if (-not $entry) { return $null }
        $reader = New-Object IO.StreamReader $entry.Open()
        $text = $reader.ReadToEnd()
        $reader.Close()
      } finally { $zip.Dispose() }
    } else { return $null }
  } catch { return $null }

  $text = $text -replace "`r`n ", "" -replace "`n ", ""
  $h = @{}
  foreach ($line in $text -split "`r?`n") {
    $i = $line.IndexOf(':')
    if ($i -gt 0) { $h[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim() }
  }
  return $h
}

# Tach danh sach phan cach bang dau phay, bo qua dau phay nam trong ngoac kep
# (vi du version="[1.0,2.0)" co dau phay ben trong).
function Split-Clauses([string] $value) {
  if (-not $value) { return @() }
  $out = @(); $buf = ""; $quoted = $false
  foreach ($ch in $value.ToCharArray()) {
    if ($ch -eq '"') { $quoted = -not $quoted }
    if ($ch -eq ',' -and -not $quoted) { $out += $buf; $buf = "" } else { $buf += $ch }
  }
  if ($buf) { $out += $buf }
  return $out | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
}

function Get-ClauseName([string] $clause) { return ($clause -split ';')[0].Trim() }
function Test-Optional([string] $clause) { return ($clause -replace '\s','') -match 'resolution:=optional' }

<#
  Khoa dinh danh cua mot capability, dang "<namespace>=<gia tri>".

  Provide-Capability: osgi.extender;osgi.extender="osgi.component";version:Version="1.5"
  Require-Capability: osgi.extender;filter:="(&(osgi.extender=osgi.component)(version>=1.0))"

  Ca hai deu quy ve "osgi.extender=osgi.component". Chi can khop den muc nay la
  du cho viec gom bundle; khong can hien thuc bo loc LDAP day du.
#>
function Get-CapabilityKey([string] $clause) {
  $ns = Get-ClauseName $clause
  if (-not $ns) { return $null }

  # osgi.ee do chinh JVM cung cap, osgi.native do framework; khong bundle nao ca.
  if ($ns -eq "osgi.ee" -or $ns -eq "osgi.native") { return $null }

  # Yeu cau danh dau effective:=active chi duoc xet luc chay, khong phai luc resolve.
  if (($clause -replace '\s','') -match 'effective:=active') { return $null }

  $m = [regex]::Match($clause, [regex]::Escape($ns) + '\s*=\s*"?([^";,()]+)"?')
  if (-not $m.Success) { return $null }
  return "$ns=" + $m.Groups[1].Value.Trim()
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

Write-Host ""
Write-Host "Doc manifest cua nen tang..."
$all = @{}        # symbolic name -> duong dan
$exports = @{}      # ten package -> symbolic name
$fragments = @{}    # host -> danh sach fragment
$capabilities = @{} # "<namespace>=<gia tri>" -> symbolic name

foreach ($item in @(Get-ChildItem $srcPlugins) + @(Get-ChildItem $plugins)) {
  if ($item.Name -like "*.source_*") { continue }
  $h = Read-BundleHeaders $item.FullName
  if (-not $h -or -not $h["Bundle-SymbolicName"]) { continue }
  $sn = Get-ClauseName $h["Bundle-SymbolicName"]
  if ($all.ContainsKey($sn)) { continue }
  $all[$sn] = @{ Path = $item.FullName; Headers = $h }
  foreach ($c in Split-Clauses $h["Export-Package"]) {
    $pkg = Get-ClauseName $c
    if (-not $exports.ContainsKey($pkg)) { $exports[$pkg] = $sn }
  }
  foreach ($c in Split-Clauses $h["Provide-Capability"]) {
    $key = Get-CapabilityKey $c
    if ($key -and -not $capabilities.ContainsKey($key)) { $capabilities[$key] = $sn }
  }
  if ($h["Fragment-Host"]) {
    $host_ = Get-ClauseName $h["Fragment-Host"]
    if (-not $fragments.ContainsKey($host_)) { $fragments[$host_] = @() }
    $fragments[$host_] += $sn
  }
}
Write-Host "  quet duoc $($all.Count) bundle"

<#
  Goc cua bao dong.

  Sau bundle dau la cua RSSOwl. Phan con lai la khung khoi dong cong voi cac
  plugin nam trong feature org.rssowl.dependencies: chung duoc dung qua extension
  point chu khong qua Require-Bundle, nen khong the suy ra tu manifest.
#>
$roots = @(
  "org.rssowl.core", "org.rssowl.ui",
  "org.rssowl.lib.db4o", "org.rssowl.lib.httpclient",
  "org.rssowl.lib.jdom", "org.rssowl.lib.lucene.queryparser",

  "org.eclipse.osgi", "org.eclipse.equinox.simpleconfigurator",
  "org.eclipse.equinox.launcher", "org.eclipse.equinox.common",
  "org.eclipse.core.runtime", "org.eclipse.ui",

  "org.eclipse.ui.net", "org.eclipse.ui.forms",
  "org.eclipse.core.net", "org.eclipse.equinox.security",
  "org.eclipse.equinox.event",

  # Dinh nghia theme e4_default. Khong co no thi moi lan khoi dong deu ghi
  # "Theme 'org.eclipse.e4.ui.css.theme.e4_default' not found" vao log. Bundle
  # nay chi chua CSS, khong mang branding cua Eclipse nhu org.eclipse.platform.
  "org.eclipse.ui.themes"
)

$needed = New-Object 'System.Collections.Generic.HashSet[string]'
$queue = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($r in $roots) { $queue.Enqueue($r) }
$missing = @()

while ($queue.Count -gt 0) {
  $sn = $queue.Dequeue()
  if ($needed.Contains($sn)) { continue }
  if (-not $all.ContainsKey($sn)) { $missing += $sn; continue }
  [void] $needed.Add($sn)

  $h = $all[$sn].Headers
  foreach ($c in Split-Clauses $h["Require-Bundle"]) {
    if (-not (Test-Optional $c)) { $queue.Enqueue((Get-ClauseName $c)) }
  }
  foreach ($c in Split-Clauses $h["Import-Package"]) {
    if (Test-Optional $c) { continue }
    $owner = $exports[(Get-ClauseName $c)]
    if ($owner) { $queue.Enqueue($owner) }
  }
  <#
    Require-Capability cung phai di theo, khong chi Require-Bundle va
    Import-Package. Bo qua no thi thieu org.apache.felix.scr - bundle hien thuc
    Declarative Services, thu ma org.eclipse.equinox.event doi qua
    osgi.extender=osgi.component. Hau qua khi thieu: app khong khoi dong duoc
    va khong ghi ra file log nao ca.
  #>
  foreach ($c in Split-Clauses $h["Require-Capability"]) {
    if (Test-Optional $c) { continue }
    $key = Get-CapabilityKey $c
    if ($key -and $capabilities.ContainsKey($key)) { $queue.Enqueue($capabilities[$key]) }
  }
  # Fragment di theo host: SWT va launcher deu can fragment win32 cua chung.
  foreach ($f in $fragments[$sn]) { $queue.Enqueue($f) }
}

if ($missing.Count -gt 0) {
  Write-Host "  khong tim thay (bo qua): $($missing -join ', ')" -ForegroundColor DarkYellow
}

Write-Host "  RSSOwl can $($needed.Count) bundle"

# Chep nhung bundle cua nen tang chua co trong dist
$copied = 0
foreach ($sn in $needed) {
  $src = $all[$sn].Path
  if ($src -like "$plugins*") { continue }   # bundle cua RSSOwl, da dat roi
  $leaf = Split-Path $src -Leaf
  $dest = Join-Path $plugins $leaf
  if (Test-Path $src -PathType Container) { Copy-Tree $src $dest } else { Copy-Item $src $dest -Force }
  $copied++
}
$pluginSize = (Get-ChildItem $plugins -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("  chep $copied bundle cua nen tang, tong plugins/ {0:N1} MB" -f ($pluginSize / 1MB))

# --- 4. JRE rut gon ----------------------------------------------------------
<#
  Danh sach module: giu rong rai, vi mot module thieu KHONG bao loi ro rang.
  Da vap that: thieu jdk.management thi org.apache.lucene.core khong resolve
  (no import com.sun.management), keo theo analysis-common, org.rssowl.core,
  org.rssowl.ui, va thong bao cuoi cung chi la
  "Application org.rssowl.ui.rssowl could not be found in the registry" -
  khong he nhac den module nao. Dung bot module nao thi phai chay that lai.

  jdk.localedata + include-locales: can cho dinh dang ngay thang tieng Viet.
  jdk.unsupported: db4o 6.1 va cac thu vien doi cu cham vao sun.misc.
  jdk.crypto.ec: TLS cho feed HTTPS.
#>
$modules = @(
  "java.base", "java.desktop", "java.xml", "java.naming", "java.management",
  "java.logging", "java.prefs", "java.sql", "java.net.http", "java.security.jgss",
  "java.security.sasl", "java.scripting", "java.datatransfer", "java.instrument",
  "java.compiler", "java.rmi", "java.transaction.xa",
  "jdk.management", "jdk.unsupported", "jdk.crypto.ec", "jdk.crypto.cryptoki",
  "jdk.zipfs", "jdk.localedata", "jdk.charsets", "jdk.security.auth", "jdk.net",
  "jdk.httpserver", "jdk.xml.dom", "jdk.accessibility"
) -join ","

Write-Host ""
Write-Host "Dung JRE rut gon bang jlink..."
$jreDir = Join-Path $OutDir "jre"
& (Join-Path $JavaHome "bin\jlink.exe") --add-modules $modules --include-locales=en,vi `
  --strip-debug --no-header-files --no-man-pages --compress=zip-6 --output $jreDir
if ($LASTEXITCODE -ne 0) { Fail "jlink that bai." }
$jreSize = (Get-ChildItem $jreDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("  JRE {0:N1} MB" -f ($jreSize / 1MB))

# --- 5. launcher -------------------------------------------------------------
Write-Host ""
Write-Host "Launcher:"
Copy-Item (Join-Path $EclipseHome "eclipse.exe") (Join-Path $OutDir "RSSOwl.exe") -Force

<#
  Doi icon cua launcher.

  IconExe chi thay duoc icon nao tim thay muc CUNG kich thuoc va cung do sau mau
  trong file .ico, va no KHONG doc duoc muc nen PNG (bao "Error 40"). Launcher
  cua Eclipse co mot icon 256x256 ma rssowl.ico ban 2006 khong co, nen neu dung
  thang file goc thi icon Eclipse 256x256 con sot lai. Ham nay giu nguyen 9 muc
  cu va them mot muc 256x256 dang DIB.
#>
function New-LauncherIcon([string] $srcIco, [string] $srcPng, [string] $outIco) {
  Add-Type -AssemblyName System.Drawing

  $bytes = [IO.File]::ReadAllBytes($srcIco)
  $count = [BitConverter]::ToUInt16($bytes, 4)
  $old = @()
  for ($i = 0; $i -lt $count; $i++) {
    $o = 6 + 16 * $i
    $len = [BitConverter]::ToUInt32($bytes, $o + 8)
    $off = [BitConverter]::ToUInt32($bytes, $o + 12)
    $hdr = New-Object byte[] 16
    [Array]::Copy($bytes, $o, $hdr, 0, 16)
    $data = New-Object byte[] $len
    [Array]::Copy($bytes, $off, $data, 0, $len)
    $old += ,@{ Header = $hdr; Data = $data }
  }

  $src = [Drawing.Bitmap]::FromFile($srcPng)
  $bmp = New-Object Drawing.Bitmap 256, 256, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src, 0, 0, 256, 256)
  $g.Dispose(); $src.Dispose()

  # BITMAPINFOHEADER + du lieu XOR (BGRA, tu duoi len) + mat na AND
  $ms = New-Object IO.MemoryStream
  $bw = New-Object IO.BinaryWriter $ms
  $bw.Write([UInt32]40); $bw.Write([Int32]256); $bw.Write([Int32]512)  # cao gap doi: XOR + AND
  $bw.Write([UInt16]1);  $bw.Write([UInt16]32)
  $bw.Write([UInt32]0);  $bw.Write([UInt32](256 * 256 * 4))
  $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
  for ($y = 255; $y -ge 0; $y--) {
    for ($x = 0; $x -lt 256; $x++) {
      $c = $bmp.GetPixel($x, $y)
      $bw.Write([Byte]$c.B); $bw.Write([Byte]$c.G); $bw.Write([Byte]$c.R); $bw.Write([Byte]$c.A)
    }
  }
  # Mat na AND: 1bpp, moi hang dem cho tron 4 byte. Anh 32-bit dung alpha nen de 0.
  $bw.Write((New-Object byte[] (([Math]::Ceiling(256 / 8 / 4) * 4) * 256)))
  $bw.Flush()
  $dib = $ms.ToArray()
  $bw.Close(); $bmp.Dispose()

  $n = $count + 1
  $fs = [IO.File]::Create($outIco)
  $w = New-Object IO.BinaryWriter $fs
  $w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$n)
  $offset = 6 + 16 * $n
  foreach ($e in $old) {
    $h = $e.Header.Clone()
    [Array]::Copy([BitConverter]::GetBytes([UInt32]$e.Data.Length), 0, $h, 8, 4)
    [Array]::Copy([BitConverter]::GetBytes([UInt32]$offset), 0, $h, 12, 4)
    $w.Write($h)
    $offset += $e.Data.Length
  }
  $w.Write([Byte]0); $w.Write([Byte]0); $w.Write([Byte]0); $w.Write([Byte]0)
  $w.Write([UInt16]1); $w.Write([UInt16]32)
  $w.Write([UInt32]$dib.Length); $w.Write([UInt32]$offset)
  foreach ($e in $old) { $w.Write($e.Data) }
  $w.Write($dib)
  $w.Close(); $fs.Close()
}

$iconDir = Join-Path $root "org.rssowl.ui\icons\product"
$launcherIco = Join-Path $OutDir "rssowl.ico"
New-LauncherIcon (Join-Path $iconDir "rssowl.ico") (Join-Path $iconDir "128x128.png") $launcherIco

# IconExe nam trong chinh target platform, khong phai cai them gi.
$publisher = Get-ChildItem $srcPlugins -Filter "org.eclipse.equinox.p2.publisher.eclipse_*.jar" |
             Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
if (-not $publisher) { Fail "Khong thay bundle p2.publisher.eclipse (chua IconExe)." }

$iconLog = & (Join-Path $JavaHome "bin\java.exe") -cp $publisher.FullName `
  org.eclipse.pde.internal.swt.tools.IconExe (Join-Path $OutDir "RSSOwl.exe") $launcherIco 2>&1
if ($iconLog -match "not replaced") {
  $iconLog | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
  Fail "IconExe khong thay het icon - file .ico thieu kich thuoc nao do."
}
Write-Host "  RSSOwl.exe, da doi icon"

# --- 6. file nhan dang san pham ----------------------------------------------
<#
  Eclipse dat ten thu muc configuration rieng cua nguoi dung theo noi dung file
  nay (~/.eclipse/<id>_<version>_<hash>). De nguyen thi thu muc do mang ten
  "org.eclipse.platform" va hai ban RSSOwl khac nhau se dam vao nhau.
#>
@(
  "name=RSSOwl"
  "id=org.rssowl.ui"
  "version=$version"
) -join "`r`n" | Set-Content (Join-Path $OutDir ".eclipseproduct") -Encoding ASCII

# --- 7. configuration --------------------------------------------------------
$osgi = (Get-ChildItem $plugins -Filter "org.eclipse.osgi_*.jar" | Select-Object -First 1).Name
if (-not $osgi) { Fail "Khong thay org.eclipse.osgi trong $plugins" }
$simple = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.simpleconfigurator_*.jar" | Select-Object -First 1).Name
if (-not $simple) { Fail "Khong thay simpleconfigurator trong $plugins" }

$cfgDir = Join-Path $OutDir "configuration"

# Lay start level tu chinh ban Eclipse dung lam target platform, thay vi dat
# cung trong script - xem chu thich cua Get-StartLevels.
$startLevels = Get-StartLevels (Join-Path $EclipseHome "configuration\org.eclipse.equinox.simpleconfigurator\bundles.info")
Write-BundlesInfo $plugins (Join-Path $cfgDir "org.eclipse.equinox.simpleconfigurator\bundles.info") $null $startLevels

<#
  Khong dat osgi.configuration.area o day. Khi cai vao Program Files thu muc cai
  dat la chi-doc, va Equinox tu chuyen sang mot configuration area ghi duoc trong
  ~/.eclipse roi doc thu muc nay lam ban dung chung. Da thu that voi mot thu muc
  bi tu choi quyen ghi: app khoi dong binh thuong. Dat tay bien do se lam
  simpleconfigurator khong tim thay bundles.info nua.

  osgi.instance.area.default thi PHAI co: ban phat hanh khong truyen -data, thieu
  no thi Eclipse hoi nguoi dung chon workspace luc khoi dong.
#>
@(
  "osgi.framework=file\:plugins/$osgi"
  "osgi.bundles=reference\:file\:$simple@1\:start"
  "org.eclipse.equinox.simpleconfigurator.configUrl=file\:org.eclipse.equinox.simpleconfigurator/bundles.info"
  "osgi.bundles.defaultStartLevel=4"
  "eclipse.product=org.rssowl.ui.product"
  "eclipse.application=org.rssowl.ui.rssowl"
  "osgi.splashPath=platform\:/base/plugins/org.rssowl.ui"
  "osgi.instance.area.default=@user.home/.rssowl2"
) -join "`r`n" | Set-Content (Join-Path $cfgDir "config.ini") -Encoding ASCII

# --- 8. RSSOwl.ini -----------------------------------------------------------
<#
  Ten file ini phai trung ten exe, launcher tim theo ten do.
  -vm phai la duong dan TUONG DOI: eclipse.ini trong cay phat trien tro thang
  vao JDK cua may nay, mang di may khac la chet.
#>
@(
  "-startup"
  "plugins/" + (Get-ChildItem $plugins -Filter "org.eclipse.equinox.launcher_*.jar" | Select-Object -First 1).Name
  "--launcher.library"
  "plugins/" + (Get-ChildItem $plugins -Directory -Filter "org.eclipse.equinox.launcher.win32.win32.x86_64_*" | Select-Object -First 1).Name
  "-vm"
  "jre\bin\javaw.exe"
  "-vmargs"
  "-Xms40m"
  "-Xmx512m"
  # db4o 6.1 reflect vao field noi bo cua java.lang.Enum de luu enum. Tu JDK 16
  # strong encapsulation chan viec do, nem InaccessibleObjectException ngay khi
  # doc preferences luc khoi dong.
  "--add-opens=java.base/java.lang=ALL-UNNAMED"
  "--add-opens=java.base/java.util=ALL-UNNAMED"
  "--add-opens=java.base/java.io=ALL-UNNAMED"
) -join "`r`n" | Set-Content (Join-Path $OutDir "RSSOwl.ini") -Encoding ASCII

# --- 9. ghi chu giay phep ----------------------------------------------------
<#
  Lay nguyen van phan <license><text> trong rssowl.product lam LICENSE.txt de
  trinh cai dat hien thi. Lay tu day chu khong go lai, de chi co mot nguon su
  that duy nhat cho phan phap ly.
#>
$productXml = [xml](Get-Content (Join-Path $root "org.rssowl.ui\rssowl.product") -Raw)
$licenseText = $productXml.product.license.text
if ($licenseText) {
  ($licenseText -replace "`n", "`r`n").Trim() |
    Set-Content (Join-Path $OutDir "LICENSE.txt") -Encoding UTF8
  Write-Host ""
  Write-Host "  LICENSE.txt lay tu rssowl.product"
}

# --- 10. tong ket ------------------------------------------------------------
$total = (Get-ChildItem $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host ("Xong: $OutDir  ({0:N1} MB)" -f ($total / 1MB)) -ForegroundColor Green
Write-Host "Chay thu:  $OutDir\RSSOwl.exe"

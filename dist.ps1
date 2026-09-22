<#
  Build a complete RSSOwl product folder for Inno Setup to package.

  How this differs from run.ps1: run.ps1 lays RSSOwl's bundles into a full copy
  of the Eclipse SDK (332 MB, 696 bundles) - convenient for development, but
  not something to ship. This script takes only the bundles RSSOwl actually
  needs, computed as the transitive closure over Require-Bundle /
  Import-Package / Require-Capability, which comes to about 84 bundles / 42 MB.

  The output also carries a JRE trimmed with jlink, so the target machine does
  not need Java installed. The module list below was verified by actually
  running the app, not inferred from documentation - see the comment on
  jdk.management.

  Examples:
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

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

. (Join-Path $root "build-common.ps1")

# --- 0. environment ----------------------------------------------------------
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-21*" -and (Test-Path (Join-Path $_.FullName "bin\jlink.exe")) } |
              Select-Object -First 1 -ExpandProperty FullName
}
if (-not $JavaHome) { Fail "No JDK 21 with jlink found. Pass -JavaHome." }
$JavaHome = $JavaHome.TrimEnd('\')
if (-not (Test-Path (Join-Path $JavaHome "bin\jlink.exe"))) { Fail "No jlink in $JavaHome" }
if (-not (Test-Path (Join-Path $EclipseHome "plugins"))) { Fail "No target platform at $EclipseHome" }

$srcPlugins = Join-Path $EclipseHome "plugins"
$version = Get-BundleVersion (Join-Path $root "org.rssowl.ui")

Write-Host "RSSOwl $version | JDK $JavaHome | target $EclipseHome"
Write-Host ""

# --- 1. compile --------------------------------------------------------------
if (-not $SkipBuild) {
  & (Join-Path $root "build.ps1") -Clean
  if ($LASTEXITCODE -ne 0) { Fail "Compilation failed." }
}
if (-not (Test-Path $build)) { Fail "No $build. Run .\build.ps1 first." }

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
$plugins = Join-Path $OutDir "plugins"
New-Item -ItemType Directory -Force -Path $plugins | Out-Null

# --- 2. RSSOwl's bundles -----------------------------------------------------
Write-Host "RSSOwl bundles:"
Copy-RssOwlBundles $root $build $plugins

# --- 3. transitive closure over the platform bundles -------------------------
<#
  Read the OSGi headers of a bundle, whether it is a folder or a jar.
  Continuation lines in MANIFEST.MF start with exactly one space and have to be
  joined back before splitting headers, otherwise a long Require-Bundle gets
  truncated.
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

# Split a comma-separated list, ignoring commas inside quotes (for example
# version="[1.0,2.0)" has a comma inside).
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
  The identifying key of a capability, as "<namespace>=<value>".

  Provide-Capability: osgi.extender;osgi.extender="osgi.component";version:Version="1.5"
  Require-Capability: osgi.extender;filter:="(&(osgi.extender=osgi.component)(version>=1.0))"

  Both reduce to "osgi.extender=osgi.component". Matching to that level is
  enough for collecting bundles; a full LDAP filter implementation is not
  needed.
#>
function Get-CapabilityKey([string] $clause) {
  $ns = Get-ClauseName $clause
  if (-not $ns) { return $null }

  # osgi.ee is provided by the JVM itself and osgi.native by the framework; no
  # bundle provides either.
  if ($ns -eq "osgi.ee" -or $ns -eq "osgi.native") { return $null }

  # Requirements marked effective:=active are only considered at runtime, not
  # at resolve time.
  if (($clause -replace '\s','') -match 'effective:=active') { return $null }

  $m = [regex]::Match($clause, [regex]::Escape($ns) + '\s*=\s*"?([^";,()]+)"?')
  if (-not $m.Success) { return $null }
  return "$ns=" + $m.Groups[1].Value.Trim()
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

Write-Host ""
Write-Host "Reading the platform's manifests..."
$all = @{}          # symbolic name -> path
$exports = @{}      # package name -> symbolic name
$fragments = @{}    # host -> list of fragments
$capabilities = @{} # "<namespace>=<value>" -> symbolic name

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
Write-Host "  scanned $($all.Count) bundles"

<#
  Roots of the closure.

  The first six are RSSOwl's own. The rest are the boot framework plus the
  plug-ins from the org.rssowl.dependencies feature: those are used through
  extension points rather than Require-Bundle, so they cannot be derived from
  the manifests.
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

  # Defines the e4_default theme. Without it every startup logs
  # "Theme 'org.eclipse.e4.ui.css.theme.e4_default' not found". This bundle
  # holds CSS only; it does not carry Eclipse branding the way
  # org.eclipse.platform does.
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
    Require-Capability has to be followed too, not just Require-Bundle and
    Import-Package. Skipping it loses org.apache.felix.scr - the bundle that
    implements Declarative Services, which org.eclipse.equinox.event asks for
    through osgi.extender=osgi.component. When it is missing the app does not
    start and writes no log file at all.
  #>
  foreach ($c in Split-Clauses $h["Require-Capability"]) {
    if (Test-Optional $c) { continue }
    $key = Get-CapabilityKey $c
    if ($key -and $capabilities.ContainsKey($key)) { $queue.Enqueue($capabilities[$key]) }
  }
  # Fragments follow their host: both SWT and the launcher need their win32
  # fragment.
  foreach ($f in $fragments[$sn]) { $queue.Enqueue($f) }
}

if ($missing.Count -gt 0) {
  Write-Host "  not found (skipped): $($missing -join ', ')" -ForegroundColor DarkYellow
}

Write-Host "  RSSOwl needs $($needed.Count) bundles"

# Copy the platform bundles that are not in dist yet
$copied = 0
foreach ($sn in $needed) {
  $src = $all[$sn].Path
  if ($src -like "$plugins*") { continue }   # an RSSOwl bundle, already laid down
  $leaf = Split-Path $src -Leaf
  $dest = Join-Path $plugins $leaf
  if (Test-Path $src -PathType Container) { Copy-Tree $src $dest } else { Copy-Item $src $dest -Force }
  $copied++
}
$pluginSize = (Get-ChildItem $plugins -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("  copied {0} platform bundles, plugins/ totals {1:N1} MB" -f $copied, ($pluginSize / 1MB))

# --- 4. trimmed JRE ----------------------------------------------------------
<#
  Module list: keep it generous, because a missing module does NOT produce a
  clear error. Learned the hard way: without jdk.management,
  org.apache.lucene.core does not resolve (it imports com.sun.management),
  which drags down analysis-common, org.rssowl.core and org.rssowl.ui, and the
  final message is just "Application org.rssowl.ui.rssowl could not be found in
  the registry" - with no mention of any module. Dropping a module from this
  list means running the app for real again.

  jdk.localedata + include-locales: needed for Vietnamese date formatting.
  jdk.unsupported: db4o 6.1 and other old libraries reach into sun.misc.
  jdk.crypto.ec: TLS for HTTPS feeds.
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
Write-Host "Building a trimmed JRE with jlink..."
$jreDir = Join-Path $OutDir "jre"
& (Join-Path $JavaHome "bin\jlink.exe") --add-modules $modules --include-locales=en,vi `
  --strip-debug --no-header-files --no-man-pages --compress=zip-6 --output $jreDir
if ($LASTEXITCODE -ne 0) { Fail "jlink failed." }
$jreSize = (Get-ChildItem $jreDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ("  JRE {0:N1} MB" -f ($jreSize / 1MB))

# --- 5. launcher -------------------------------------------------------------
Write-Host ""
Write-Host "Launcher:"
Copy-Item (Join-Path $EclipseHome "eclipse.exe") (Join-Path $OutDir "RSSOwl.exe") -Force

<#
  Replace the launcher's icon.

  IconExe can only replace an icon for which it finds an entry of the SAME size
  and the same colour depth in the .ico file, and it can NOT read PNG-compressed
  entries (it reports "Error 40"). Eclipse's launcher has a 256x256 icon that
  the 2006-era rssowl.ico does not, so using the original file as-is leaves
  Eclipse's 256x256 icon behind. This function keeps the 9 existing entries and
  appends a 256x256 one in DIB form.
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

  # BITMAPINFOHEADER + XOR data (BGRA, bottom-up) + AND mask
  $ms = New-Object IO.MemoryStream
  $bw = New-Object IO.BinaryWriter $ms
  $bw.Write([UInt32]40); $bw.Write([Int32]256); $bw.Write([Int32]512)  # double height: XOR + AND
  $bw.Write([UInt16]1);  $bw.Write([UInt16]32)
  $bw.Write([UInt32]0);  $bw.Write([UInt32](256 * 256 * 4))
  $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
  for ($y = 255; $y -ge 0; $y--) {
    for ($x = 0; $x -lt 256; $x++) {
      $c = $bmp.GetPixel($x, $y)
      $bw.Write([Byte]$c.B); $bw.Write([Byte]$c.G); $bw.Write([Byte]$c.R); $bw.Write([Byte]$c.A)
    }
  }
  # AND mask: 1bpp, each row padded to a multiple of 4 bytes. A 32-bit image
  # uses its alpha channel, so leave the mask at 0.
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

# IconExe lives in the target platform itself, nothing extra to install.
$publisher = Get-ChildItem $srcPlugins -Filter "org.eclipse.equinox.p2.publisher.eclipse_*.jar" |
             Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1
if (-not $publisher) { Fail "No p2.publisher.eclipse bundle (which contains IconExe)." }

$iconLog = & (Join-Path $JavaHome "bin\java.exe") -cp $publisher.FullName `
  org.eclipse.pde.internal.swt.tools.IconExe (Join-Path $OutDir "RSSOwl.exe") $launcherIco 2>&1
if ($iconLog -match "not replaced") {
  $iconLog | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
  Fail "IconExe did not replace every icon - the .ico file is missing a size."
}
Write-Host "  RSSOwl.exe, icon replaced"

# --- 6. product identification file ------------------------------------------
<#
  Eclipse names the user's own configuration folder after the contents of this
  file (~/.eclipse/<id>_<version>_<hash>). Left alone, that folder would be
  called "org.eclipse.platform" and two different RSSOwl builds would collide
  in it.
#>
@(
  "name=RSSOwl"
  "id=org.rssowl.ui"
  "version=$version"
) -join "`r`n" | Set-Content (Join-Path $OutDir ".eclipseproduct") -Encoding ASCII

# --- 7. configuration --------------------------------------------------------
$osgi = (Get-ChildItem $plugins -Filter "org.eclipse.osgi_*.jar" | Select-Object -First 1).Name
if (-not $osgi) { Fail "No org.eclipse.osgi in $plugins" }
$simple = (Get-ChildItem $plugins -Filter "org.eclipse.equinox.simpleconfigurator_*.jar" | Select-Object -First 1).Name
if (-not $simple) { Fail "No simpleconfigurator in $plugins" }

$cfgDir = Join-Path $OutDir "configuration"

# Take the start levels from the Eclipse build used as the target platform
# instead of hard-coding them here - see the comment on Get-StartLevels.
$startLevels = Get-StartLevels (Join-Path $EclipseHome "configuration\org.eclipse.equinox.simpleconfigurator\bundles.info")
Write-BundlesInfo $plugins (Join-Path $cfgDir "org.eclipse.equinox.simpleconfigurator\bundles.info") $null $startLevels

<#
  Do not set osgi.configuration.area here. When installed into Program Files
  the install folder is read-only, and Equinox moves to a writable
  configuration area under ~/.eclipse on its own, reading this folder as the
  shared one. Verified for real against a folder with write permission denied:
  the app starts fine. Setting the variable by hand stops simpleconfigurator
  from finding bundles.info.

  osgi.instance.area.default, on the other hand, is REQUIRED: the release does
  not pass -data, and without it Eclipse asks the user to pick a workspace at
  startup.
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
  The ini file has to be named after the exe; that is how the launcher finds it.
  -vm must be a RELATIVE path: eclipse.ini in the development tree points
  straight at this machine's JDK, which is fatal on any other machine.
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
  # db4o 6.1 reflects into internal fields of java.lang.Enum to store enums. As
  # of JDK 16 strong encapsulation blocks that, throwing
  # InaccessibleObjectException as soon as preferences are read at startup.
  "--add-opens=java.base/java.lang=ALL-UNNAMED"
  "--add-opens=java.base/java.util=ALL-UNNAMED"
  "--add-opens=java.base/java.io=ALL-UNNAMED"
) -join "`r`n" | Set-Content (Join-Path $OutDir "RSSOwl.ini") -Encoding ASCII

# --- 9. license notice -------------------------------------------------------
<#
  Take the <license><text> section of rssowl.product verbatim as LICENSE.txt
  for the installer to display. Taken from there rather than retyped, so there
  is a single source of truth for the legal text.
#>
$productXml = [xml](Get-Content (Join-Path $root "org.rssowl.ui\rssowl.product") -Raw)
$licenseText = $productXml.product.license.text
if ($licenseText) {
  ($licenseText -replace "`n", "`r`n").Trim() |
    Set-Content (Join-Path $OutDir "LICENSE.txt") -Encoding UTF8
  Write-Host ""
  Write-Host "  LICENSE.txt taken from rssowl.product"
}

# --- 10. summary -------------------------------------------------------------
$total = (Get-ChildItem $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host ("Done: $OutDir  ({0:N1} MB)" -f ($total / 1MB)) -ForegroundColor Green
Write-Host "Try it:  $OutDir\RSSOwl.exe"

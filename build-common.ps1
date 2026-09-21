<#
  Phan dung chung giua run.ps1 (runtime de phat trien) va dist.ps1 (ban phat hanh).

  Vi sao tach ra: ca hai deu phai dat sau bundle cua RSSOwl vao mot thu muc
  plugins/ theo dung chuan OSGi, va viec do co nhung chi tiet de quen - resource
  nam lan trong src/, ten thu muc phai mang phien ban, bundle cu phai xoa han
  thay vi ghi de. Neu hai script tu lam lay thi ban phat hanh se khac ban da
  kiem thu bang run.ps1, va do la thu khong ai phat hien ra cho den khi phat hanh.

  Dot-source file nay; no can mot ham Fail($msg) da duoc dinh nghia san.
#>

# robocopy tra ve 0-7 khi thanh cong; chi tu 8 tro len moi la loi.
function Copy-Tree($from, $to, [string[]] $excludeFiles) {
  if (-not (Test-Path $from)) { return }
  $a = @($from, $to, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
  if ($excludeFiles) { $a += "/XF"; $a += $excludeFiles }
  robocopy @a | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "robocopy that bai ($from -> $to), ma $LASTEXITCODE" }
}

<#
  Doc phien ban tu chinh manifest cua bundle. Truoc day ten thu muc cua
  org.rssowl.core va org.rssowl.ui bi viet cung "2.1.0.qualifier" trong script,
  nen nang phien ban trong MANIFEST.MF se lam deploy lech ma khong bao loi.
#>
function Get-BundleVersion([string] $projDir) {
  $manifest = Join-Path $projDir "META-INF\MANIFEST.MF"
  if (-not (Test-Path $manifest)) { Fail "Khong thay $manifest" }
  $v = Get-Content $manifest | Where-Object { $_ -match '^Bundle-Version:\s*(.+)$' } |
       ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
  if (-not $v) { Fail "Khong doc duoc Bundle-Version tu $manifest" }
  return $v
}

<#
  Dat sau bundle cua RSSOwl vao $Plugins.

  $Root   = goc cay source, $Build = build-out\main, $Plugins = thu muc dich.
#>
function Copy-RssOwlBundles([string] $Root, [string] $Build, [string] $Plugins) {

  # Xoa moi bundle org.rssowl.* da dat truoc do, bat ke phien ban nao. Ten thu
  # muc mang phien ban, nen khi nang phien ban thu muc cu khong bi ghi de ma nam
  # lai; buoc dung bundles.info quet ca thu muc plugins/ nen se liet ke ca hai
  # ban, va hai ban cua mot bundle singleton thi khong resolve duoc.
  foreach ($stale in Get-ChildItem $Plugins -Directory -Filter "org.rssowl.*" -ErrorAction SilentlyContinue) {
    Remove-Item $stale.FullName -Recurse -Force
  }

  # --- hai bundle co source --------------------------------------------------
  # Thu muc dat ten <symbolic-name>_<version> dung chuan OSGi. Chuoi "qualifier"
  # chi duoc thay the luc build chinh thuc, de nguyen o runtime la hop le.
  foreach ($b in @(
    @{ Proj = "org.rssowl.core"; Pkg = "org\rssowl\core";
       Files = @("plugin.xml", "plugin.properties", "about.html"); Dirs = @("schema") },
    @{ Proj = "org.rssowl.ui";   Pkg = "org\rssowl\ui";
       Files = @("plugin.xml", "plugin.properties", "about.html", "about.ini",
                 "preferences.ini", "splash.bmp", "default_feeds.xml"); Dirs = @("icons", "schema") }
  )) {
    $src  = Join-Path $Root $b.Proj
    $dest = Join-Path $Plugins "$($b.Proj)_$(Get-BundleVersion $src)"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

    Copy-Tree (Join-Path $src "META-INF") (Join-Path $dest "META-INF")
    foreach ($d in $b.Dirs)  { Copy-Tree (Join-Path $src $d) (Join-Path $dest $d) }
    foreach ($f in $b.Files) {
      $p = Join-Path $src $f
      if (Test-Path $p) { Copy-Item $p $dest -Force }
    }

    # Class da bien dich.
    Copy-Tree (Join-Path $Build $b.Pkg) (Join-Path $dest $b.Pkg)

    # messages.properties va entities.dtd nam lan trong src, khong co chung thi
    # NLS nem MissingResourceException ngay luc khoi dong.
    Copy-Tree (Join-Path $src "src") $dest @("*.java")

    $n = @(Get-ChildItem $dest -Recurse -Filter *.class).Count
    $r = @(Get-ChildItem $dest -Recurse -Include *.properties, *.dtd).Count
    Write-Host ("  {0,-20} {1} class, {2} resource" -f $b.Proj, $n, $r)
  }

  # --- bon bundle thu vien ---------------------------------------------------
  # Chep theo dung bin.includes cua tung bundle: chi cay .class va META-INF.
  foreach ($lib in @(
    # Ba bundle cu mang san cay .class da giai nen; file .jar cua chung chi de
    # tham chieu source va khong nam tren Bundle-ClassPath.
    @{ Proj = "org.rssowl.lib.db4o";       Skip = @("*.jar", "src.zip") },
    @{ Proj = "org.rssowl.lib.httpclient"; Skip = @("*.jar", "src.zip") },
    @{ Proj = "org.rssowl.lib.jdom";       Skip = @("*.jar", "src.zip") },

    # Query parser boc mot jar CO nam tren Bundle-ClassPath, nen phai giu lai.
    @{ Proj = "org.rssowl.lib.lucene.queryparser"; Skip = @() }
  )) {
    $src = Join-Path $Root $lib.Proj

    # Doc phien ban tu chinh bundle thay vi gia dinh tat ca dung chung mot so.
    $version = Get-BundleVersion $src

    $dest = Join-Path $Plugins "$($lib.Proj)_$version"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Tree $src $dest ($lib.Skip + @("build.properties", ".classpath", ".project"))

    $classes = @(Get-ChildItem $dest -Recurse -Filter *.class).Count
    $jars = @(Get-ChildItem $dest -Filter *.jar).Count
    Write-Host ("  {0,-34} {1} class{2}" -f $lib.Proj, $classes, $(if ($jars) { ", $jars jar" } else { "" }))
  }
}

<#
  Doc start level tu mot bundles.info co san: id -> "<muc>,<da-start>".

  Vi sao phai doc chu khong dat cung: mot so bundle ha tang BAT BUOC phai duoc
  start va start som (simpleconfigurator o muc 1, felix.scr va equinox.event o
  muc 2...). Danh sach do la chuyen cua Eclipse, khong phai cua RSSOwl, va no
  doi theo tung ban. Doan sai thi bundle van resolve nhung service khong bao gio
  duoc dang ky - bieu hien la "no actual value was found for the argument
  IEventBroker" luc dung workbench, khong he nhac den start level.
#>
function Get-StartLevels([string] $bundlesInfoPath) {
  $map = @{}
  if (-not (Test-Path $bundlesInfoPath)) { return $map }
  foreach ($line in Get-Content $bundlesInfoPath) {
    if ($line.StartsWith("#")) { continue }
    $f = $line -split ','
    if ($f.Count -ge 5) { $map[$f[0]] = "$($f[3]),$($f[4])" }
  }
  return $map
}

<#
  Ghi lai bundles.info: danh sach ma org.eclipse.equinox.simpleconfigurator doc
  luc khoi dong.

  $Existing   = bundles.info san co; neu co thi giu nguyen moi dong khong phai
                org.rssowl.* va chi thay phan cua RSSOwl (dung cho run.ps1, noi
                runtime la mot ban Eclipse day du).
  $StartLevels = bang tra start level (xem Get-StartLevels); dung khi sinh moi
                hoan toan tu $Plugins (dung cho dist.ps1).
#>
function Write-BundlesInfo([string] $Plugins, [string] $Target, [string] $Existing, [hashtable] $StartLevels) {
  if ($Existing -and (Test-Path $Existing)) {
    $lines = @(Get-Content $Existing | Where-Object { $_ -notmatch '^org\.rssowl\.' })
    foreach ($dir in Get-ChildItem $Plugins -Directory -Filter "org.rssowl.*") {
      $lines += (Format-BundleLine $dir.Name $true $StartLevels)
    }
  } else {
    $lines = @("#encoding=UTF-8", "#version=1")
    foreach ($item in Get-ChildItem $Plugins) {
      $line = Format-BundleLine $item.Name $item.PSIsContainer $StartLevels
      if ($line) { $lines += $line }
    }
  }

  New-Item -ItemType Directory -Force -Path (Split-Path $Target -Parent) | Out-Null
  $lines -join "`r`n" | Set-Content $Target -Encoding ASCII
}

<#
  Mot dong bundles.info: id,version,duong-dan,start-level,da-start.

  Ten thu muc/jar la <symbolic-name>_<version>; tach o dau gach duoi CUOI CUNG
  vi ban than symbolic name cung chua dau gach duoi.
#>
function Format-BundleLine([string] $name, [bool] $isDir, [hashtable] $StartLevels) {
  if (-not $isDir) {
    if (-not $name.EndsWith(".jar")) { return $null }
    $name = $name.Substring(0, $name.Length - 4)
  }

  $split = $name.LastIndexOf('_')
  if ($split -lt 0) { return $null }
  $id = $name.Substring(0, $split)
  $version = $name.Substring($split + 1)

  # Bundle dang thu muc phai co dau / o cuoi duong dan.
  $path = "plugins/$name" + $(if ($isDir) { "/" } else { ".jar" })

  $level = "4,false"
  if ($StartLevels -and $StartLevels.ContainsKey($id)) { $level = $StartLevels[$id] }

  return "$id,$version,$path,$level"
}

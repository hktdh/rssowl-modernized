<#
  Shared between run.ps1 (development runtime) and dist.ps1 (release build).

  Why it is factored out: both have to lay RSSOwl's bundles into a plugins/
  folder the way OSGi expects, and that has details which are easy to forget -
  resources living among the sources in src/, folder names that must carry the
  version, stale bundles that must be deleted rather than overwritten. If each
  script did this on its own, the release would differ from what run.ps1 was
  tested with, and nobody would notice until release day.

  Dot-source this file; it expects a Fail($msg) function to already exist.
#>

# robocopy returns 0-7 on success; only 8 and above is a failure.
function Copy-Tree($from, $to, [string[]] $excludeFiles) {
  if (-not (Test-Path $from)) { return }
  $a = @($from, $to, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
  if ($excludeFiles) { $a += "/XF"; $a += $excludeFiles }
  robocopy @a | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "robocopy failed ($from -> $to), code $LASTEXITCODE" }
}

<#
  Read the version from the bundle's own manifest. The folder names for
  org.rssowl.core and org.rssowl.ui used to be hard-coded as "2.1.0.qualifier"
  in the script, so bumping the version in MANIFEST.MF made the deployment
  inconsistent without reporting any error.
#>
function Get-BundleVersion([string] $projDir) {
  $manifest = Join-Path $projDir "META-INF\MANIFEST.MF"
  if (-not (Test-Path $manifest)) { Fail "No $manifest" }
  $v = Get-Content $manifest | Where-Object { $_ -match '^Bundle-Version:\s*(.+)$' } |
       ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1
  if (-not $v) { Fail "Could not read Bundle-Version from $manifest" }
  return $v
}

<#
  Lay RSSOwl's bundles into $Plugins.

  $Root = source tree root, $Build = build-out\main, $Plugins = destination.
#>
function Copy-RssOwlBundles([string] $Root, [string] $Build, [string] $Plugins) {

  # Delete every org.rssowl.* bundle deployed earlier, whatever its version.
  # Folder names carry the version, so after a version bump the old folder is
  # not overwritten but stays behind; the bundles.info step scans the whole
  # plugins/ folder and would list both, and two copies of a singleton bundle
  # do not resolve.
  foreach ($stale in Get-ChildItem $Plugins -Directory -Filter "org.rssowl.*" -ErrorAction SilentlyContinue) {
    Remove-Item $stale.FullName -Recurse -Force
  }

  # --- the two bundles that have sources -------------------------------------
  # The folder is named <symbolic-name>_<version> as OSGi expects. The literal
  # "qualifier" is only substituted in an official build; leaving it at runtime
  # is valid.
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

    # Compiled classes.
    Copy-Tree (Join-Path $Build $b.Pkg) (Join-Path $dest $b.Pkg)

    # messages.properties and entities.dtd live among the sources; without them
    # NLS throws MissingResourceException right at startup.
    Copy-Tree (Join-Path $src "src") $dest @("*.java")

    $n = @(Get-ChildItem $dest -Recurse -Filter *.class).Count
    $r = @(Get-ChildItem $dest -Recurse -Include *.properties, *.dtd).Count
    Write-Host ("  {0,-20} {1} classes, {2} resources" -f $b.Proj, $n, $r)
  }

  # --- the four library bundles ----------------------------------------------
  # Copy exactly what each bundle's bin.includes says: only the .class tree and
  # META-INF.
  foreach ($lib in @(
    # Three old bundles ship an already extracted .class tree; their .jar files
    # are there for source reference only and are not on the Bundle-ClassPath.
    @{ Proj = "org.rssowl.lib.db4o";       Skip = @("*.jar", "src.zip") },
    @{ Proj = "org.rssowl.lib.httpclient"; Skip = @("*.jar", "src.zip") },
    @{ Proj = "org.rssowl.lib.jdom";       Skip = @("*.jar", "src.zip") },

    # The query parser wraps a jar that IS on the Bundle-ClassPath, so keep it.
    @{ Proj = "org.rssowl.lib.lucene.queryparser"; Skip = @() }
  )) {
    $src = Join-Path $Root $lib.Proj

    # Read the version from the bundle itself instead of assuming they all
    # share one number.
    $version = Get-BundleVersion $src

    $dest = Join-Path $Plugins "$($lib.Proj)_$version"
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Tree $src $dest ($lib.Skip + @("build.properties", ".classpath", ".project"))

    $classes = @(Get-ChildItem $dest -Recurse -Filter *.class).Count
    $jars = @(Get-ChildItem $dest -Filter *.jar).Count
    Write-Host ("  {0,-34} {1} classes{2}" -f $lib.Proj, $classes, $(if ($jars) { ", $jars jar" } else { "" }))
  }
}

<#
  Read start levels from an existing bundles.info: id -> "<level>,<started>".

  Why read them rather than hard-code: some infrastructure bundles MUST be
  started, and started early (simpleconfigurator at level 1, felix.scr and
  equinox.event at level 2, ...). That list belongs to Eclipse, not to RSSOwl,
  and it shifts between releases. Guess wrong and the bundles still resolve but
  the services are never registered - which shows up as "no actual value was
  found for the argument IEventBroker" when the workbench starts, with no
  mention of start levels at all.
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
  Write bundles.info: the list org.eclipse.equinox.simpleconfigurator reads at
  startup.

  $Existing    = an existing bundles.info; when given, every line that is not
                 org.rssowl.* is kept as-is and only RSSOwl's part is replaced
                 (used by run.ps1, where the runtime is a full Eclipse).
  $StartLevels = start level lookup table (see Get-StartLevels); used when
                 generating the file from scratch out of $Plugins (dist.ps1).
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
  One bundles.info line: id,version,path,start-level,started.

  Folder and jar names are <symbolic-name>_<version>; split at the LAST
  underscore, because the symbolic name contains underscores itself.
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

  # A bundle deployed as a folder needs a trailing / on its path.
  $path = "plugins/$name" + $(if ($isDir) { "/" } else { ".jar" })

  $level = "4,false"
  if ($StartLevels -and $StartLevels.ContainsKey($id)) { $level = $StartLevels[$id] }

  return "$id,$version,$path,$level"
}

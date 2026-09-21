<#
  Deploy RSSOwl 2.1 thanh mot Eclipse RCP runtime doc lap roi chay.

  Cach hoat dong: org.rssowl.ui/config.ini goc dung org.eclipse.update.configurator
  (co che doi Eclipse 3.x, tu quet thu muc plugins/) chu khong dung p2. Nho vay chi
  can dat bundle vao plugins/ la runtime tu nhan ra, khong phai dung ke hoach p2 nao.
  Script nay tai lap dung mo hinh do.

  Runtime la ban sao rieng cua Eclipse SDK (-RuntimeHome), khong dung vao ban SDK
  dung lam target platform, de IDE va app chay doc lap nhau.

  Vi du:
    .\run.ps1                  # build, deploy, chay
    .\run.ps1 -SkipBuild       # deploy lai va chay, bo qua buoc bien dich
    .\run.ps1 -DeployOnly      # chi deploy, khong chay
#>
[CmdletBinding()]
param(
  [string] $RuntimeHome = "D:\CDS\tools\rssowl-run",
  [string] $JavaHome    = $env:JAVA_HOME,
  [string] $DataDir     = "D:\CDS\build\rssowl-data",
  [switch] $SkipBuild,
  [switch] $DeployOnly
)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$build = Join-Path $root "build-out\main"

function Fail($msg) { Write-Host "LOI: $msg" -ForegroundColor Red; exit 1 }

# Ghim JDK 8 giong build.ps1: Equinox 3.8 co truoc Java 9 va khong khoi dong
# dang tin cay tren JDK moi. JAVA_HOME cap May bi trinh cai JDK khac ghi de.
if (-not $JavaHome) {
  $JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "jdk-8*" -and (Test-Path (Join-Path $_.FullName "bin\java.exe")) } |
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

# robocopy tra ve 0-7 khi thanh cong; chi tu 8 tro len moi la loi.
function Copy-Tree($from, $to, [string[]] $excludeFiles) {
  if (-not (Test-Path $from)) { return }
  $a = @($from, $to, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
  if ($excludeFiles) { $a += "/XF"; $a += $excludeFiles }
  robocopy @a | Out-Null
  if ($LASTEXITCODE -ge 8) { Fail "robocopy that bai ($from -> $to), ma $LASTEXITCODE" }
}

$plugins = Join-Path $RuntimeHome "plugins"

# --- 2. hai bundle co source -------------------------------------------------
# Thu muc dat ten <symbolic-name>_<version> dung chuan OSGi. Chuoi "qualifier"
# chi duoc thay the luc build chinh thuc, de nguyen o runtime la hop le.
foreach ($b in @(
  @{ Proj = "org.rssowl.core"; Pkg = "org\rssowl\core";
     Files = @("plugin.xml", "plugin.properties", "about.html"); Dirs = @("schema") },
  @{ Proj = "org.rssowl.ui";   Pkg = "org\rssowl\ui";
     Files = @("plugin.xml", "plugin.properties", "about.html", "about.ini",
               "preferences.ini", "splash.bmp", "default_feeds.xml"); Dirs = @("icons", "schema") }
)) {
  $src  = Join-Path $root $b.Proj
  $dest = Join-Path $plugins "$($b.Proj)_2.1.0.qualifier"
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

  Copy-Tree (Join-Path $src "META-INF") (Join-Path $dest "META-INF")
  foreach ($d in $b.Dirs)  { Copy-Tree (Join-Path $src $d) (Join-Path $dest $d) }
  foreach ($f in $b.Files) {
    $p = Join-Path $src $f
    if (Test-Path $p) { Copy-Item $p $dest -Force }
  }

  # Class da bien dich.
  Copy-Tree (Join-Path $build $b.Pkg) (Join-Path $dest $b.Pkg)

  # messages.properties va entities.dtd nam lan trong src, khong co chung thi
  # NLS nem MissingResourceException ngay luc khoi dong.
  Copy-Tree (Join-Path $src "src") $dest @("*.java")

  $n = @(Get-ChildItem $dest -Recurse -Filter *.class).Count
  $r = @(Get-ChildItem $dest -Recurse -Include *.properties, *.dtd).Count
  Write-Host ("  {0,-20} {1} class, {2} resource" -f $b.Proj, $n, $r)
}

# --- 3. bon bundle thu vien --------------------------------------------------
# Chep theo dung bin.includes cua tung bundle: chi cay .class va META-INF.
# Cac file .jar khong nam tren Bundle-ClassPath (chung chi de tham chieu source),
# nen bo qua de runtime nhe hon.
foreach ($lib in @("db4o", "httpclient", "jdom", "lucene")) {
  $proj = "org.rssowl.lib.$lib"
  $dest = Join-Path $plugins "${proj}_2.1.0.qualifier"
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Copy-Tree (Join-Path $root $proj) $dest @("*.jar", "src.zip", "build.properties", ".classpath", ".project")
  Write-Host ("  {0,-20} {1} class" -f $proj, @(Get-ChildItem $dest -Recurse -Filter *.class).Count)
}

# --- 4. config.ini -----------------------------------------------------------
$osgi = (Get-ChildItem $plugins -Filter "org.eclipse.osgi_*.jar" |
         Where-Object { $_.Name -notlike "*.source_*" } | Select-Object -First 1).Name
if (-not $osgi) { Fail "Khong thay bundle org.eclipse.osgi trong $plugins" }

$cfgDir = Join-Path $RuntimeHome "configuration"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

# Khong khai org.eclipse.update.reconcile=false: can configurator quet plugins/
# moi lan chay thi no moi thay cac bundle RSSOwl vua deploy.
@(
  "osgi.framework=file\:plugins/$osgi"
  "osgi.bundles=org.eclipse.equinox.common@2\:start,org.eclipse.update.configurator@3\:start,org.eclipse.core.runtime@start"
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
  "-Xms15m"
  "-Xmx192m"        # dung dinh muc trong rssowl.product
  # Khong dat -XX:MaxPermSize: JDK 8 da bo PermGen, chi to ra canh bao thua.
) -join "`r`n" | Set-Content (Join-Path $RuntimeHome "eclipse.ini") -Encoding ASCII

Write-Host "Deploy xong vao $RuntimeHome" -ForegroundColor Green
if ($DeployOnly) { exit 0 }

# --- 5. chay -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Write-Host "Dang chay RSSOwl (data: $DataDir)..."
Start-Process -FilePath (Join-Path $RuntimeHome "eclipse.exe") `
  -ArgumentList "-data", $DataDir, "-clean", "-consolelog" | Out-Null

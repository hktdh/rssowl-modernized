; RSSOwl installer for Windows, built with Inno Setup 6.
;
; The input is the folder produced by dist.ps1 (.\dist by default). Compile with:
;   .\dist.ps1
;   & "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" rssowl.iss
;
; Or call package.ps1 to do both steps.
;
; What is here reproduces exactly the registration the old NSIS installer did
; (org.rssowl.ui/rssowl_installer.nsi): shortcuts, the uninstall entry, and the
; feed: protocol handler.

#define AppName      "RSSOwl"
#define AppPublisher "RSSOwl.org"
#define AppURL       "http://www.rssowl.org/"
#define AppExe       "RSSOwl.exe"

#ifndef DistDir
  #define DistDir "dist"
#endif

; package.ps1 reads the version from MANIFEST.MF and passes it in with
; /DAppVersion=... The value below is only a fallback for calling ISCC directly.
#ifndef AppVersion
  #define AppVersion "2.2.0"
#endif

[Setup]
; AppId identifies the product across upgrades - do NOT change this value;
; changing it makes Windows treat this as different software and leave the old
; installation in place.
AppId={{9F1B4C0E-6A2D-4E7A-9C3F-2B8E5D14A7C6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=build-out
OutputBaseFilename={#AppName}-{#AppVersion}-setup
SetupIconFile={#DistDir}\rssowl.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile={#DistDir}\LICENSE.txt
WizardStyle=modern
DisableProgramGroupPage=yes

; Installs for every user on the machine -> needs admin rights.
PrivilegesRequired=admin

; The build is 64-bit (both the SWT fragment and the JRE are x86_64), it does
; not run on 32-bit.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Strong compression: most of the payload is the JRE, which compresses very
; well.
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "feedprotocol"; Description: "Open feed:// links with RSSOwl"; GroupDescription: "System integration:"

[Files]
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\rssowl.ico"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\rssowl.ico"; Tasks: desktopicon

[Registry]
; The feed: protocol handler, same as the old NSIS build. Only registered when
; the user opts in.
Root: HKLM; Subkey: "Software\Classes\feed"; ValueType: string; ValueName: ""; ValueData: "URL:feed Protocol"; Flags: uninsdeletekey; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"""; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: feedprotocol

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Equinox may write into configuration/ when running with admin rights; those
; files were not created by the installer, so they have to be removed by hand.
Type: filesandordirs; Name: "{app}\configuration"
Type: dirifempty; Name: "{app}"

; User data (feeds, index, preferences) lives in %USERPROFILE%\.rssowl2 and is
; deliberately NOT deleted: uninstalling and reinstalling keeps the feeds.

[Code]

{ RSSOwl uses the SWT Browser, and on Windows SWT picks Edge (WebView2) first,
  falling back to Internet Explorer only when there is no WebView2 runtime.
  That IE path is barely tested any more, and the reading pane has been broken
  outright on it, so warn up front instead of letting the user run into a
  broken UI. }
function WebView2Installed(): Boolean;
var
  Value: String;
begin
  Result :=
    RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value) or
    RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value) or
    RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', Value);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not WebView2Installed() then
    Result := MsgBox(
      'Microsoft Edge WebView2 Runtime was not found on this machine.' + #13#10#13#10 +
      'RSSOwl uses it to display news content. Without it the reading pane may' + #13#10 +
      'not render correctly. You can install the WebView2 Runtime from' + #13#10 +
      'Microsoft and then run this installer again.' + #13#10#13#10 +
      'Continue with the installation anyway?',
      mbConfirmation, MB_YESNO) = IDYES;
end;

{ An older build leaves the previous version's bundles behind in plugins/, and
  OSGi cannot resolve two versions of the same singleton bundle - the app does
  not start. So these three folders have to be deleted outright before the new
  files are copied, rather than copied over. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  AppDir: String;
begin
  if CurStep = ssInstall then
  begin
    AppDir := ExpandConstant('{app}');
    DelTree(AppDir + '\plugins', True, True, True);
    DelTree(AppDir + '\features', True, True, True);
    DelTree(AppDir + '\configuration', True, True, True);
    DelTree(AppDir + '\jre', True, True, True);
  end;
end;

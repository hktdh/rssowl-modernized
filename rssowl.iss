; Trinh cai dat RSSOwl cho Windows, dung Inno Setup 6.
;
; Dau vao la thu muc do dist.ps1 dung ra (mac dinh .\dist). Bien dich bang:
;   .\dist.ps1
;   & "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" rssowl.iss
;
; Hoac goi package.ps1 de lam ca hai buoc.
;
; Nhung gi o day tai lap lai dung phan dang ky cua trinh cai NSIS cu
; (org.rssowl.ui/rssowl_installer.nsi): shortcut, muc go cai dat, va bo xu ly
; giao thuc feed:.

#define AppName      "RSSOwl"
#define AppPublisher "RSSOwl.org"
#define AppURL       "http://www.rssowl.org/"
#define AppExe       "RSSOwl.exe"

#ifndef DistDir
  #define DistDir "dist"
#endif

; package.ps1 doc phien ban tu MANIFEST.MF roi truyen vao bang /DAppVersion=...
; Gia tri duoi day chi la duong lui khi goi ISCC truc tiep.
#ifndef AppVersion
  #define AppVersion "2.2.0"
#endif

[Setup]
; AppId dinh danh san pham qua cac ban nang cap - KHONG doi gia tri nay,
; doi la Windows se coi day la mot phan mem khac va khong go ban cu.
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

; Cai cho moi nguoi dung trong may -> can quyen admin.
PrivilegesRequired=admin

; Ban dung la 64-bit (fragment SWT va JRE deu x86_64), khong chay tren 32-bit.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Nen manh: phan lon dung luong la JRE, nen rat tot.
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "feedprotocol"; Description: "Mo lien ket feed:// bang RSSOwl"; GroupDescription: "Lien ket he thong:"

[Files]
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\rssowl.ico"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\rssowl.ico"; Tasks: desktopicon

[Registry]
; Bo xu ly giao thuc feed:, giong ban NSIS cu. Chi dang ky khi nguoi dung chon.
Root: HKLM; Subkey: "Software\Classes\feed"; ValueType: string; ValueName: ""; ValueData: "URL:feed Protocol"; Flags: uninsdeletekey; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"""; Tasks: feedprotocol
Root: HKLM; Subkey: "Software\Classes\feed\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: feedprotocol

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Equinox co the ghi them vao configuration/ khi chay voi quyen admin; nhung
; file do khong do trinh cai tao ra nen phai don tay.
Type: filesandordirs; Name: "{app}\configuration"
Type: dirifempty; Name: "{app}"

; Du lieu cua nguoi dung (feed, chi muc, tuy chon) nam o %USERPROFILE%\.rssowl2
; va CO Y khong bi xoa: go cai dat roi cai lai thi nguoi dung van con feed.

[Code]

{ RSSOwl dung SWT Browser, va tren Windows SWT chon Edge (WebView2) truoc, chi
  lui ve Internet Explorer khi khong co WebView2 runtime. Nhanh IE do gan nhu
  khong con duoc chay thu, va khung doc tin tung hong han o do, nen bao truoc
  cho nguoi dung thay vi de ho gap giao dien vo. }
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
      'Khong tim thay Microsoft Edge WebView2 Runtime tren may nay.' + #13#10#13#10 +
      'RSSOwl dung no de hien thi noi dung tin. Thieu no thi khung doc tin co the' + #13#10 +
      'khong hien dung. Ban co the cai WebView2 Runtime tu trang cua Microsoft,' + #13#10 +
      'roi chay lai trinh cai dat nay.' + #13#10#13#10 +
      'Van tiep tuc cai dat?',
      mbConfirmation, MB_YESNO) = IDYES;
end;

{ Ban cu de lai bundle cua phien ban truoc trong plugins/, va hai phien ban cua
  cung mot bundle singleton thi OSGi khong resolve duoc - app khong khoi dong.
  Vi vay phai xoa han ba thu muc nay truoc khi chep ban moi, thay vi chep de. }
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

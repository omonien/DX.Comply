; DX.Comply Setup for Delphi 13 (RAD Studio 37.0)
; Installs BPLs, DCPs, and CLI tool into a user-local directory
; and registers the IDE package in the Delphi 13 Known Packages.

#define MyAppName "DX.Comply"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "Olaf Monien"
#define MyAppURL "https://github.com/omonien/DX.Comply"
#define BDSVersion "37.0"
#define DelphiName "Delphi 13"
#define DllSuffix "370"
#define BDSRegKey "SOFTWARE\Embarcadero\BDS\" + BDSVersion

[Setup]
AppId={{F4A7E2B1-8C3D-4E5F-9A1B-2C3D4E5F6A7B}
AppName={#MyAppName} for {#DelphiName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\build\setup
OutputBaseFilename=DX.Comply.D13.Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
WizardStyle=modern
SetupIconFile=..\assets\DX.Comply.ico
UninstallDisplayIcon={app}\DX.Comply.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
english.BeveledLabel=DX.Comply - CRA Compliance for Delphi
german.BeveledLabel=DX.Comply - CRA-Compliance für Delphi

[Files]
; BPLs and DCPs
Source: "..\build\Win32\Release\DX.Comply.Engine{#DllSuffix}.bpl"; DestDir: "{app}\bpl"; Flags: ignoreversion
Source: "..\build\Win32\Release\DX.Comply.IDE{#DllSuffix}.bpl"; DestDir: "{app}\bpl"; Flags: ignoreversion
Source: "..\build\Win32\Release\dcu\DX.Comply.Engine.dcp"; DestDir: "{app}\dcp"; Flags: ignoreversion
Source: "..\build\Win32\Release\dcu\DX.Comply.IDE.dcp"; DestDir: "{app}\dcp"; Flags: ignoreversion
; CLI tool
Source: "..\build\Win32\Release\DX.Comply.CLI.exe"; DestDir: "{app}\bin"; DestName: "dxcomply.exe"; Flags: ignoreversion
; Documentation
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
; Icon
Source: "..\assets\DX.Comply.ico"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; Register IDE BPL in Known Packages (HKCU — no admin required)
Root: HKCU; Subkey: "{#BDSRegKey}\Known Packages"; ValueType: string; ValueName: "{app}\bpl\DX.Comply.IDE{#DllSuffix}.bpl"; ValueData: "DX.Comply CRA Compliance Documentation"; Flags: uninsdeletevalue
; Add BPL directory to the IDE search path so the Engine BPL is found at runtime
Root: HKCU; Subkey: "{#BDSRegKey}\Environment Variables"; ValueType: string; ValueName: "DXCOMPLY"; ValueData: "{app}\bpl"; Flags: uninsdeletevalue

[Code]
function IsDelphi13Installed: Boolean;
begin
  Result := RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Embarcadero\BDS\{#BDSVersion}') or
            RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\Embarcadero\BDS\{#BDSVersion}') or
            RegKeyExists(HKEY_CURRENT_USER, 'SOFTWARE\Embarcadero\BDS\{#BDSVersion}');
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if not IsDelphi13Installed then
  begin
    MsgBox('{#DelphiName} (RAD Studio {#BDSVersion}) was not found on this system.' + #13#10 + #13#10 +
           'This installer only supports {#DelphiName}.' + #13#10 +
           'Please install {#DelphiName} first, or use the CLI tool (dxcomply.exe) ' +
           'from the release ZIP for other Delphi versions.',
           mbError, MB_OK);
    Result := False;
  end;
end;

[Run]
Filename: "{app}\README.md"; Description: "View README"; Flags: postinstall shellexec skipifsilent unchecked

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

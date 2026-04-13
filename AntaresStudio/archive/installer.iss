#define MyAppName "AntaresStudio"
#define MyAppVersion "8.0.0"
#define MyAppExeName "AntaresStudio.exe"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=AntaresLab
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

OutputDir=installer_out
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersion}

Compression=lzma
SolidCompression=yes
WizardStyle=modern

ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64compatible

DisableProgramGroupPage=yes

; app.ico yoksa bu 2 satırı sil
SetupIconFile=app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstüne kısayol oluştur"; GroupDescription: "Kısayollar:"; Flags: unchecked

[Files]
; ---------------- APP (FINAL RELEASE) ----------------
Source: "release\AntaresStudio\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; ---------------- VC++ RUNTIME ----------------
; tools\VC_redist.x64.exe dosyasını proje köküne göre koymalısın.
Source: "tools\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName} (Console)"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Kaldır"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; VC++ kurulu değilse sessiz kur
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "VC++ Runtime kuruluyor..."; Check: NeedsVCRedist64

; Kurulum bitince app’i çalıştır
Filename: "{app}\{#MyAppExeName}"; Description: "{#MyAppName}'yu çalıştır"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsVCRedist64: Boolean;
var
  Installed: Cardinal;
begin
  Result := True;

  { VC++ 2015-2022 x64 runtime registry check }
  if RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed', Installed) then
  begin
    if Installed = 1 then
      Result := False;
  end;
end;

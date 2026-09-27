#define MyAppName "AntaresStudio"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AntaresLab"
#define MyAppExeName "AntaresStudio.exe"

[Setup]
AppId={{A1D3B2A4-5B6C-4D7E-8F90-123456789ABC}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

OutputDir=installer
OutputBaseFilename=AntaresStudio_Setup
Compression=lzma2
SolidCompression=yes

SetupIconFile=app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=no

[Tasks]
Name: "desktopicon"; Description: "Masaüstü kısayolu oluştur"; GroupDescription: "Kısayollar:"; Flags: unchecked

[Files]
Source: "dist_base\{#MyAppName}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{#MyAppName}'i çalıştır"; Flags: nowait postinstall skipifsilent

[Setup]
; Uygulama Bilgileri
AppName=AntaresStudio IoT
AppVersion=2.1.0
AppVerName=AntaresStudio IoT v2.1.0
AppPublisher=Antares Laboratory
AppPublisherURL=https://github.com/ScRien/antareslab
AppSupportURL=https://github.com/ScRien/antareslab/issues
DefaultDirName={autopf}\AntaresStudio
DefaultGroupName=AntaresStudio
DisableProgramGroupPage=yes

; Çıktı
OutputDir=output
OutputBaseFilename=AntaresStudio_Setup_v2.1.0
SetupIconFile=assets\app.ico
UninstallDisplayIcon={app}\app\antares_studio_iot.exe

; Sıkıştırma
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

; İzinler
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Görünüm
WizardStyle=modern
WizardSizePercent=110
DisableWelcomePage=no
ShowLanguageDialog=auto

; Lisans
LicenseFile=assets\LICENSE.txt

; Windows sürüm gereksinimleri
MinVersion=10.0

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
turkish.BeveledLabel=AntaresStudio IoT - Otonom Dijital İkiz Stüdyosu

[Tasks]
Name: "desktopicon"; Description: "Masaüstüne kısayol oluştur"; GroupDescription: "Ek görevler:"
Name: "startmenu"; Description: "Başlat menüsüne ekle"; GroupDescription: "Ek görevler:"

[Files]
; Flutter Uygulaması
Source: "internal\app\*"; DestDir: "{app}\app"; Flags: ignoreversion recursesubdirs createallsubdirs
; Python Backend
Source: "internal\backend\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs createallsubdirs
; Assets
Source: "assets\app.ico"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
; Backend veri dizinleri (yazma izinli)
Name: "{app}\backend\data"; Permissions: users-modify
Name: "{app}\backend\data\uploads"; Permissions: users-modify
Name: "{app}\backend\data\cleaned"; Permissions: users-modify
Name: "{app}\backend\data\output"; Permissions: users-modify
Name: "{app}\backend\data\models"; Permissions: users-modify
Name: "{app}\backend\data\meshroom_cache"; Permissions: users-modify

[Icons]
; Masaüstü kısayolu
Name: "{commondesktop}\AntaresStudio"; Filename: "{app}\app\antares_studio_iot.exe"; IconFilename: "{app}\app.ico"; Tasks: desktopicon; Comment: "AntaresStudio IoT - Otonom Dijital İkiz Stüdyosu"
; Başlat menüsü
Name: "{group}\AntaresStudio"; Filename: "{app}\app\antares_studio_iot.exe"; IconFilename: "{app}\app.ico"; Tasks: startmenu
; Kaldırma
Name: "{group}\AntaresStudio Kaldır"; Filename: "{uninstallexe}"

[Run]
; Kurulum sonrası uygulamayı başlat
Filename: "{app}\app\antares_studio_iot.exe"; Description: "AntaresStudio'yu başlat"; Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
; Kaldırma sırasında backend'i durdur
Filename: "taskkill"; Parameters: "/F /IM antares_backend.exe"; Flags: runhidden; RunOnceId: "KillBackend"

[UninstallDelete]
; Kaldırma sırasında veri dizinlerini temizle (isteğe bağlı)
Type: filesandordirs; Name: "{app}\backend\data"

[Code]
// Kurulum başlamadan önce eski backend processleri kapat
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // Çalışan backend'i durdur
    Exec('taskkill', '/F /IM antares_backend.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    // Çalışan uygulama'yı durdur
    Exec('taskkill', '/F /IM antares_studio_iot.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

// Önceki sürüm kuruluysa uyar
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
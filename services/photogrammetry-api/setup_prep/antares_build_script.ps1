<# 
.SYNOPSIS
    AntaresStudio IoT - Uretim Paketleme Scripti (Build & Package)

.DESCRIPTION
    Bu script tum uretim paketleme surecini otomatize eder:
      1. Flutter Windows Release Build
      2. Python Backend PyInstaller Freeze
      3. Dosyalari setup_prep/ altina topla
      4. Inno Setup ile kurulum dosyasi olustur (istege bagli)

.USAGE
    .\setup_prep\antares_build_script.ps1
    .\setup_prep\antares_build_script.ps1 -SkipBackend
    .\setup_prep\antares_build_script.ps1 -SkipFlutter
    .\setup_prep\antares_build_script.ps1 -BuildInstaller
#>

param(
    [switch]$SkipFlutter,
    [switch]$SkipBackend,
    [switch]$BuildInstaller,
    [switch]$CleanFirst
)

# ================================================================
# Konfigürasyon
# ================================================================

# Genel hata yonetimi Stop ama dis komutlar icin Continue yapacagiz
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $ScriptDir

# Fallback: eger ScriptDir bos ise
if (-not $ProjectRoot -or -not (Test-Path (Join-Path $ProjectRoot "apps/desktop"))) {
    $ProjectRoot = (Get-Location).Path
}

$SetupDir       = Join-Path $ProjectRoot "setup_prep"
$InternalDir    = Join-Path $SetupDir "internal"
$AppOutputDir   = Join-Path $InternalDir "app"
$BackendOutDir  = Join-Path $InternalDir "backend"
$AssetsDir      = Join-Path $SetupDir "assets"
$FlutterAppDir  = Join-Path $ProjectRoot "apps/desktop"
$BackendDir     = Join-Path $ProjectRoot "services/photogrammetry-api"

$AppName        = "AntaresStudio"
$AppVersion     = "4.0.0"
$AppExeName     = "antares_studio_iot.exe"
$BackendExeName = "antares_backend.exe"

$OneMB = 1048576  # 1MB in bytes

# ================================================================
# Yardimci Fonksiyonlar
# ================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=========================================="  -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Gray
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK]   $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FileSizeMB {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $sizeBytes = (Get-Item $FilePath).Length
        return [math]::Round($sizeBytes / $OneMB, 1)
    }
    return 0
}

function Get-DirSizeMB {
    param([string]$DirPath)
    if (Test-Path $DirPath) {
        $sizeBytes = (Get-ChildItem $DirPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($sizeBytes) {
            return [math]::Round($sizeBytes / $OneMB, 1)
        }
    }
    return 0
}

# ================================================================
# 0. Temizlik
# ================================================================

Write-Step "AntaresStudio IoT - Build v$AppVersion"
Write-Info "Proje koku: $ProjectRoot"

if ($CleanFirst -and (Test-Path $InternalDir)) {
    Write-Info "Onceki build temizleniyor..."
    Remove-Item -Recurse -Force $InternalDir
}

Ensure-Dir $AppOutputDir
Ensure-Dir $BackendOutDir
Ensure-Dir $AssetsDir

# ================================================================
# 1. Flutter Windows Release Build
# ================================================================

if (-not $SkipFlutter) {
    Write-Step "1/4 - Flutter Windows Release Build"
    
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue" # Stderr ciktilarinin scripti durdurmasini engelle
    
    try {
        $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
        Write-Info "Flutter: $flutterVersion"
    } catch {
        $ErrorActionPreference = $oldEap
        Write-Err "Flutter bulunamadi! PATH'e ekleyin."
        exit 1
    }
    
    Push-Location $FlutterAppDir
    try {
        Write-Info "flutter build windows --release ..."
        cmd.exe /c "flutter build windows --release" 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Flutter build basarisiz!"
            Pop-Location
            $ErrorActionPreference = $oldEap
            exit 1
        }
        
        # Build ciktisini setup_prep'e kopyala
        $flutterBuildDir = Join-Path $FlutterAppDir "build\windows\x64\runner\Release"
        if (-not (Test-Path $flutterBuildDir)) {
            $flutterBuildDir = Join-Path $FlutterAppDir "build\windows\runner\Release"
        }
        
        if (Test-Path $flutterBuildDir) {
            Write-Info "Flutter ciktisi kopyalaniyor..."
            Copy-Item -Path (Join-Path $flutterBuildDir "*") -Destination $AppOutputDir -Recurse -Force
            
            $exePath = Join-Path $AppOutputDir $AppExeName
            if (Test-Path $exePath) {
                $sizeMB = Get-FileSizeMB $exePath
                Write-OK "Flutter build OK: $AppExeName ($sizeMB MB)"
            } else {
                Write-Warn "Flutter exe bulunamadi: $AppExeName"
            }
        } else {
            Write-Err "Flutter build dizini bulunamadi!"
            Pop-Location
            $ErrorActionPreference = $oldEap
            exit 1
        }
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $oldEap
    }
} else {
    Write-Info "Flutter build atlandi (-SkipFlutter)"
}

# ================================================================
# 2. Python Backend PyInstaller Freeze
# ================================================================

if (-not $SkipBackend) {
    Write-Step "2/4 - Python Backend PyInstaller"
    
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue" # Stderr ciktilarinin scripti durdurmasini engelle
    
    try {
        $pythonVersion = python --version 2>&1
        Write-Info "Python: $pythonVersion"
    } catch {
        $ErrorActionPreference = $oldEap
        Write-Err "Python bulunamadi! PATH'e ekleyin."
        exit 1
    }
    
    Push-Location $BackendDir
    try {
        # PyInstaller kontrolu
        $pyiCheck = cmd.exe /c "python -m PyInstaller --version" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Info "PyInstaller kuruluyor..."
            cmd.exe /c "pip install pyinstaller" 2>&1 | Out-Null
        } else {
            Write-Info "PyInstaller: $($pyiCheck[0])"
        }
        
        # Bagimliliklari kur
        Write-Info "Python bagimliliklari kuruluyor..."
        cmd.exe /c "pip install -r requirements.txt" 2>&1 | Out-Null
        Write-OK "Bagimliliklar kontrol edildi"
        
        # PyInstaller calistir
        Write-Info "PyInstaller baslatiliyor..."
        cmd.exe /c "python -m PyInstaller antares_backend.spec --noconfirm --clean" 2>&1 | ForEach-Object { 
            Write-Host "    $_" -ForegroundColor DarkGray 
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Err "PyInstaller basarisiz!"
            Pop-Location
            $ErrorActionPreference = $oldEap
            exit 1
        }
        
        # dist ciktisini setup_prep'e kopyala
        $distDir = Join-Path $BackendDir "dist\antares_backend"
        if (Test-Path $distDir) {
            Write-Info "Backend ciktisi kopyalaniyor..."
            Copy-Item -Path (Join-Path $distDir "*") -Destination $BackendOutDir -Recurse -Force
            
            $backendExePath = Join-Path $BackendOutDir $BackendExeName
            if (Test-Path $backendExePath) {
                $sizeMB = Get-FileSizeMB $backendExePath
                Write-OK "Backend build OK: $BackendExeName ($sizeMB MB)"
            }
        } else {
            Write-Err "PyInstaller dist dizini bulunamadi!"
        }
        
        # PyInstaller gecici dosyalarini temizle
        Write-Info "PyInstaller gecici dosyalari temizleniyor..."
        $buildTemp = Join-Path $BackendDir "build"
        $distTemp = Join-Path $BackendDir "dist"
        if (Test-Path $buildTemp) { Remove-Item -Recurse -Force $buildTemp }
        if (Test-Path $distTemp) { Remove-Item -Recurse -Force $distTemp }
        Write-OK "Gecici dosyalar temizlendi"
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $oldEap
    }
} else {
    Write-Info "Backend build atlandi (-SkipBackend)"
}

# ================================================================
# 3. Assets (Icon + License)
# ================================================================

Write-Step "3/4 - Assets Hazirlaniyor"

# Lisans dosyasi
$licensePath = Join-Path $AssetsDir "LICENSE.txt"
if (Test-Path $licensePath) {
    Write-OK "LICENSE.txt mevcut"
} else {
    Write-Warn "LICENSE.txt bulunamadi, olusturuluyor..."
    Set-Content -Path $licensePath -Value "AntaresStudio IoT v$AppVersion - Tum haklari saklidir." -Encoding UTF8
    Write-OK "LICENSE.txt olusturuldu"
}

# Icon kontrolu
$iconPath = Join-Path $AssetsDir "app.ico"
if (Test-Path $iconPath) {
    Write-OK "app.ico mevcut"
} else {
    Write-Warn "app.ico bulunamadi! Lutfen setup_prep\assets\ dizinine ekleyin."
}

# ================================================================
# 4. Inno Setup (istege bagli)
# ================================================================

if ($BuildInstaller) {
    Write-Step "4/4 - Inno Setup Installer"
    
    $issPath = Join-Path $SetupDir "installer_config.iss"
    
    if (-not (Test-Path $issPath)) {
        Write-Err "installer_config.iss bulunamadi: $issPath"
        exit 1
    }
    
    # Inno Setup kontrolu
    $innoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $innoPath)) {
        $innoPath = "C:\Program Files\Inno Setup 6\ISCC.exe"
    }
    
    if (Test-Path $innoPath) {
        Write-Info "Inno Setup bulundu: $innoPath"
        Write-Info "Installer derleniyor..."
        
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue" # ISCC uyarilari durdurmasin
        
        cmd.exe /c "`"$innoPath`" `"$issPath`"" 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        
        $ErrorActionPreference = $oldEap
        
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Installer olusturuldu!"
            $outputExe = Join-Path $SetupDir "output\AntaresStudio_Setup_v$AppVersion.exe"
            if (Test-Path $outputExe) {
                $installerSize = Get-FileSizeMB $outputExe
                Write-OK "Installer: $outputExe ($installerSize MB)"
            }
        } else {
            Write-Err "Inno Setup basarisiz!"
        }
    } else {
        Write-Warn "Inno Setup bulunamadi! Lutfen Inno Setup 6 kurun."
        Write-Info "Indirme: https://jrsoftware.org/isinfo.php"
    }
} else {
    Write-Info "Installer olusturma atlandi. Kullanim: -BuildInstaller"
}

# ================================================================
# Ozet
# ================================================================

Write-Step "Build Tamamlandi!"

$appSize = Get-DirSizeMB $AppOutputDir
$backendSize = Get-DirSizeMB $BackendOutDir
$totalSize = Get-DirSizeMB $InternalDir

Write-Host "  Cikti Dizini  : $SetupDir" -ForegroundColor White
Write-Host ""
Write-Host "  internal/app/     : $appSize MB" -ForegroundColor White
Write-Host "  internal/backend/ : $backendSize MB" -ForegroundColor White
Write-Host "  TOPLAM            : $totalSize MB" -ForegroundColor Cyan
Write-Host ""

if (-not $BuildInstaller) {
    Write-Info "Installer icin: .\setup_prep\antares_build_script.ps1 -BuildInstaller"
}

Write-Host ""
Write-Host "  Build sureci tamamlandi!" -ForegroundColor Green
Write-Host ""

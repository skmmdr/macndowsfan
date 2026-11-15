param(
    [switch]$NoCopyDist
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

# Locate makensis.exe
$candidateNsisPaths = @(
    (Join-Path $root "target\nsis-3.11\nsis-3.11\makensis.exe"),
    (Join-Path $root "target\nsis-portable\nsis-3.11\makensis.exe"),
    (Join-Path $env:TEMP "kilo\nsis\nsis-3.11\makensis.exe"),
    "C:\Program Files (x86)\NSIS\makensis.exe",
    "C:\Program Files\NSIS\makensis.exe"
)

$makensis = $null
foreach ($path in $candidateNsisPaths) {
    if (Test-Path $path) {
        $makensis = $path
        break
    }
}

if (-not $makensis) {
    $cmd = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $makensis = $cmd.Source
    }
}

if (-not $makensis) {
    throw "makensis.exe not found! Please check target\nsis-3.11\nsis-3.11\makensis.exe or install NSIS."
}

Write-Host "==> Using NSIS: $makensis" -ForegroundColor Cyan

# Check prerequisites in installer\redist
$redistDir = Join-Path $root "installer\redist"
$vcRedist = Join-Path $redistDir "VC_redist.x64.exe"
$mfcSetup = Join-Path $redistDir "macsfancontrol_setup.exe"

if (-not (Test-Path $vcRedist)) {
    Write-Host "==> Downloading VC_redist.x64.exe to $vcRedist" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force $redistDir | Out-Null
    curl.exe -L "https://aka.ms/vs/17/release/vc_redist.x64.exe" -o $vcRedist
}

if (-not (Test-Path $mfcSetup)) {
    Write-Host "==> Downloading macsfancontrol_setup.exe to $mfcSetup" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force $redistDir | Out-Null
    curl.exe -L "https://crystalidea.com/downloads/macsfancontrol_setup.exe" -o $mfcSetup
}

# Ensure VC DLLs are in dist
$vcDlls = Join-Path $redistDir "vc_dlls"
$distDir = Join-Path $root "dist"
if ((Test-Path $vcDlls) -and (Test-Path $distDir)) {
    Copy-Item (Join-Path $vcDlls "*.dll") $distDir -Force
}

$nsiFile = Join-Path $root "installer\macndowsfan.nsi"
Write-Host "==> Compiling NSIS installer ($nsiFile)..." -ForegroundColor Cyan
& $makensis $nsiFile
if ($LASTEXITCODE -ne 0) {
    throw "makensis failed with exit code $LASTEXITCODE"
}

$outputExe = Join-Path $root "installer\output\macndowsfan-setup-0.3.0.exe"
if (Test-Path $outputExe) {
    $sizeMb = [Math]::Round(((Get-Item $outputExe).Length / 1MB), 2)
    Write-Host "==> Successfully created $outputExe ($sizeMb MB)" -ForegroundColor Green

    if (-not $NoCopyDist) {
        Copy-Item $outputExe $distDir -Force
        Write-Host "==> Copied to $distDir\macndowsfan-setup-0.3.0.exe" -ForegroundColor Green
    }
}

param(
    [switch]$Run,
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

# Locate flutter if not already on PATH
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $candidateFlutterDirs = @(
        (Join-Path $env:LOCALAPPDATA "dev\flutter\bin"),
        "D:\Soft\dev\flutter\bin"
    )
    foreach ($dir in $candidateFlutterDirs) {
        if (Test-Path (Join-Path $dir "flutter.bat")) {
            $env:PATH = "$dir;$env:PATH"
            break
        }
    }
}
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"

$profile = if ($Debug) { "debug" } else { "release" }

Write-Host "==> Building Rust SMC core ($profile)" -ForegroundColor Cyan
Push-Location $root
try {
    & cargo "+stable-x86_64-pc-windows-msvc" build "--$profile" --lib
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
} finally {
    Pop-Location
}

Write-Host "==> flutter pub get" -ForegroundColor Cyan
Push-Location (Join-Path $root "flutter_ui")
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    Write-Host "==> flutter build windows ($profile)" -ForegroundColor Cyan
    $args = @("build", "windows")
    if (-not $Debug) { $args += "--release" }
    & flutter @args
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
} finally {
    Pop-Location
}

$buildDirName = if ($Debug) { "Debug" } else { "Release" }
$bundle = Join-Path $root "flutter_ui\build\windows\x64\runner\$buildDirName"
$coreDll = Join-Path $root "target\$profile\macndowsfan_core.dll"

if (-not (Test-Path $bundle)) { throw "Flutter bundle not found: $bundle" }
Copy-Item $coreDll $bundle -Force

$vcDlls = Join-Path $root "installer\redist\vc_dlls"
if (Test-Path $vcDlls) {
    Copy-Item (Join-Path $vcDlls "*.dll") $bundle -Force
}
$driverSys = Join-Path $root "installer\redist\applesmc.sys"
if (Test-Path $driverSys) {
    Copy-Item $driverSys $bundle -Force
}

if (-not $Debug) {
    $dist = Join-Path $root "dist"
    if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
    New-Item -ItemType Directory -Force $dist | Out-Null
    Copy-Item (Join-Path $bundle "*") $dist -Recurse -Force
    Copy-Item $coreDll $dist -Force
    if (Test-Path $vcDlls) {
        Copy-Item (Join-Path $vcDlls "*.dll") $dist -Force
    }
    if (Test-Path $driverSys) {
        Copy-Item $driverSys $dist -Force
    }
    Write-Host "==> Built $dist\macndowsfan.exe" -ForegroundColor Green
    if ($Run) { Start-Process (Join-Path $dist "macndowsfan.exe") }
} else {
    Write-Host "==> Built $bundle\macndowsfan.exe" -ForegroundColor Green
    if ($Run) { Start-Process (Join-Path $bundle "macndowsfan.exe") }
}

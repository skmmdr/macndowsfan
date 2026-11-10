param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path $cargo)) {
    throw "cargo not found. Install Rust first: https://rustup.rs (default-host x86_64-pc-windows-gnu)"
}

$mingw = Join-Path $env:TEMP "kilo\winlibs\mingw64\bin"
if (Test-Path (Join-Path $mingw "dlltool.exe")) {
    $env:PATH = "$mingw;$env:PATH"
} elseif (-not (Get-Command dlltool.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "dlltool.exe not found. The GNU Rust target needs MinGW binutils (dlltool + as) on PATH."
    Write-Warning "Expected toolchain at $mingw, or install winlibs/MSYS2 and add its bin directory to PATH."
}

$cargoArgs = @("build")
if ($Release) { $cargoArgs += "--release" }
& $cargo @cargoArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$profile = if ($Release) { "release" } else { "debug" }
Write-Host "Built target\$profile\macndowsfan.exe"

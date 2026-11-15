param(
    [string]$InputImage = "C:\Users\tamo_levan\.gemini\antigravity\brain\58ce7c35-b44c-42b2-85d5-8d7a8288394c\macndowsfan_app_icon_1794757175349.jpg",
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path $InputImage)) {
    throw "Input image not found: $InputImage"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $InputImage).Path)

# Crop bounds around the central squircle badge (1024x1024 source)
$cropW = 760; $cropH = 760
$cropX = [int](512 - ($cropW / 2))
$cropY = [int](536 - ($cropH / 2))

# 512x512 master bitmap with squircle clip
$masterBmp = New-Object System.Drawing.Bitmap(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($masterBmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$r = 110.0
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = $r * 2
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc(512 - $d, 0, $d, $d, 270, 90)
$path.AddArc(512 - $d, 512 - $d, $d, $d, 0, 90)
$path.AddArc(0, 512 - $d, $d, $d, 90, 90)
$path.CloseFigure()

$g.SetClip($path)
$g.DrawImage($src, [System.Drawing.Rectangle]::new(0, 0, 512, 512), [System.Drawing.Rectangle]::new($cropX, $cropY, $cropW, $cropH), [System.Drawing.GraphicsUnit]::Pixel)
$g.ResetClip()
$g.Dispose()
$src.Dispose()

$pngPath = Join-Path $OutDir "macndowsfan.png"
$masterBmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Created master PNG: $pngPath" -ForegroundColor Green

# Multi-resolution ICO: 16, 24, 32, 48, 64, 128, 256
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()

foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gS = [System.Drawing.Graphics]::FromImage($bmp)
    $gS.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gS.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gS.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gS.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $gS.Clear([System.Drawing.Color]::Transparent)
    $gS.DrawImage($masterBmp, 0, 0, $s, $s)
    $gS.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += , $ms.ToArray()
    $bmp.Dispose()
    $ms.Dispose()
}

$masterBmp.Dispose()

$icoPath = Join-Path $OutDir "macndowsfan.ico"
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $bytes = $pngs[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$bytes.Length)
    $bw.Write([UInt32]$offset)
    $offset += $bytes.Length
}
foreach ($bytes in $pngs) { $bw.Write($bytes) }
$bw.Close()
$fs.Close()

Write-Host "Created multi-resolution ICO: $icoPath ($((Get-Item $icoPath).Length) bytes)" -ForegroundColor Green

# Update all icon consumers
$root = Split-Path -Parent $PSScriptRoot

# 1. Flutter Windows Runner
$runnerIco = Join-Path $root "flutter_ui\windows\runner\resources\app_icon.ico"
if (Test-Path (Split-Path -Parent $runnerIco)) {
    Copy-Item $icoPath $runnerIco -Force
    Write-Host "Updated Flutter runner icon: $runnerIco" -ForegroundColor Green
}

# 2. Dist folder assets
$distAssets = Join-Path $root "dist\data\flutter_assets\assets"
if (Test-Path $distAssets) {
    Copy-Item $icoPath $distAssets -Force
    Copy-Item $pngPath $distAssets -Force
    Write-Host "Updated dist assets: $distAssets" -ForegroundColor Green
}

# 3. Inject icon directly into dist\macndowsfan.exe
$distExe = Join-Path $root "dist\macndowsfan.exe"
if (Test-Path $distExe) {
    $csharpCode = @"
using System;
using System.IO;
using System.Runtime.InteropServices;

public class IconInjectorHelper {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cbData);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

    public static bool InjectIcon(string exePath, string icoPath) {
        byte[] icoBytes = File.ReadAllBytes(icoPath);
        if (icoBytes.Length < 6) return false;
        ushort count = BitConverter.ToUInt16(icoBytes, 4);
        IntPtr hUpdate = BeginUpdateResource(exePath, false);
        if (hUpdate == IntPtr.Zero) return false;
        byte[] grp = new byte[6 + count * 14];
        Array.Copy(icoBytes, 0, grp, 0, 6);
        for (ushort i = 0; i < count; i++) {
            int entryOffset = 6 + i * 16;
            int grpEntryOffset = 6 + i * 14;
            Array.Copy(icoBytes, entryOffset, grp, grpEntryOffset, 12);
            byte[] idBytes = BitConverter.GetBytes((ushort)(i + 1));
            Array.Copy(idBytes, 0, grp, grpEntryOffset + 12, 2);
            uint bytesInRes = BitConverter.ToUInt32(icoBytes, entryOffset + 8);
            uint imageOffset = BitConverter.ToUInt32(icoBytes, entryOffset + 12);
            byte[] imgData = new byte[bytesInRes];
            Array.Copy(icoBytes, (int)imageOffset, imgData, 0, (int)bytesInRes);
            UpdateResource(hUpdate, (IntPtr)3, (IntPtr)(i + 1), 0, imgData, bytesInRes);
        }
        UpdateResource(hUpdate, (IntPtr)14, (IntPtr)101, 0, grp, (uint)grp.Length);
        UpdateResource(hUpdate, (IntPtr)14, (IntPtr)1, 0, grp, (uint)grp.Length);
        return EndUpdateResource(hUpdate, false);
    }
}
"@
    try {
        Add-Type -TypeDefinition $csharpCode -ErrorAction SilentlyContinue
        [IconInjectorHelper]::InjectIcon($distExe, $icoPath) | Out-Null
        Write-Host "Injected icon into $distExe" -ForegroundColor Green
    } catch {}
}

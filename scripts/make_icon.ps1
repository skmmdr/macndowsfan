param(
    [string]$SourceImage,
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets")
)

$ErrorActionPreference = "Stop"

if ($SourceImage -and (Test-Path $SourceImage)) {
    & "$PSScriptRoot\convert_to_icon.ps1" -InputImage $SourceImage -OutDir $OutDir
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Drawing

New-Item -ItemType Directory -Force $OutDir | Out-Null

function New-RoundedPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $s = [single]$size
    $shell = New-RoundedPath 0 0 $s $s ([single]($s * 0.22))
    $background = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 203, 241, 160))
    $g.FillPath($background, $shell)

    # One large dark fan, with no fine detail to disappear at tray size.
    $ink = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 22, 33, 16))
    for ($i = 0; $i -lt 3; $i++) {
        $state = $g.Save()
        $g.TranslateTransform([single]($s * 0.5), [single]($s * 0.5))
        $g.RotateTransform([single]($i * 120))
        $blade = New-Object System.Drawing.Drawing2D.GraphicsPath
        $blade.AddBezier([single]0, [single](-$s * 0.035), [single](-$s * 0.15), [single](-$s * 0.13), [single](-$s * 0.06), [single](-$s * 0.34), [single]($s * 0.075), [single](-$s * 0.30))
        $blade.AddBezier([single]($s * 0.075), [single](-$s * 0.30), [single]($s * 0.20), [single](-$s * 0.25), [single]($s * 0.09), [single](-$s * 0.07), [single]0, [single](-$s * 0.035))
        $blade.CloseFigure()
        $g.FillPath($ink, $blade)
        $blade.Dispose()
        $g.Restore($state)
    }
    $hubR = [single]($s * 0.075)
    $g.FillEllipse($ink, [single]($s * 0.5 - $hubR), [single]($s * 0.5 - $hubR), [single]($hubR * 2), [single]($hubR * 2))

    $ink.Dispose()
    $background.Dispose()
    $shell.Dispose()
    $g.Dispose()
    return $bmp
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += , $ms.ToArray()
    $bmp.Dispose()
    $ms.Dispose()
}

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

$large = New-IconBitmap 512
$large.Save((Join-Path $OutDir "macndowsfan.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$large.Dispose()

Write-Host "ICO: $icoPath ($((Get-Item $icoPath).Length) bytes)"

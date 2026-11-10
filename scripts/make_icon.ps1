param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets")
)

$ErrorActionPreference = "Stop"
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

    $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $path = New-RoundedPath 0 0 ([single]$size) ([single]$size) ([single]($size * 0.22))
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 0)),
        (New-Object System.Drawing.PointF($size, $size)),
        [System.Drawing.Color]::FromArgb(255, 91, 200, 255),
        [System.Drawing.Color]::FromArgb(255, 139, 124, 255)
    )
    $g.FillPath($bg, $path)

    # Soft highlight in the upper-left corner.
    $hl = New-Object System.Drawing.Drawing2D.GraphicsPath
    $hl.AddEllipse([single](-$size * 0.35), [single](-$size * 0.55), [single]($size * 1.2), [single]($size * 0.9))
    $hlBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($hl)
    $hlBrush.CenterColor = [System.Drawing.Color]::FromArgb(55, 255, 255, 255)
    $hlBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $g.SetClip($path)
    $g.FillPath($hlBrush, $hl)
    $g.ResetClip()

    # Gauge ring with an opening at the bottom (matches the in-app gauge).
    $pad = $size * 0.225
    $arcRect = New-Object System.Drawing.RectangleF($pad, $pad, ($size - 2 * $pad), ($size - 2 * $pad))
    $stroke = [single]([Math]::Max(1.6, $size * 0.088))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, $stroke)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($pen, $arcRect, 135, 270)

    # End dot.
    $radius = ($size - 2 * $pad) / 2
    $angle = 45 * [Math]::PI / 180
    $cx = $size / 2 + $radius * [Math]::Cos($angle)
    $cy = $size / 2 + $radius * [Math]::Sin($angle)
    $dotR = [single]($size * 0.080)
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($white, [single]($cx - $dotR), [single]($cy - $dotR), [single]($dotR * 2), [single]($dotR * 2))

    # Hub.
    $hubR = [single]($size * 0.058)
    $g.FillEllipse($white, [single]($size / 2 - $hubR), [single]($size / 2 - $hubR), [single]($hubR * 2), [single]($hubR * 2))

    $white.Dispose()
    $pen.Dispose()
    $hlBrush.Dispose()
    $hl.Dispose()
    $bg.Dispose()
    $path.Dispose()
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

# Large PNG preview / README asset.
$large = New-IconBitmap 512
$large.Save((Join-Path $OutDir "macndowsfan.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$large.Dispose()

Write-Host "ICO: $icoPath ($((Get-Item $icoPath).Length) bytes)"

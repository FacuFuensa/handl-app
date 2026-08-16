# Generates the 1024x1024 app icon: cream house on terracotta, flat.
# 24bpp (no alpha channel) because App Store Connect rejects icons with alpha.
Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$terracotta = [System.Drawing.Color]::FromArgb(255, 176, 67, 31)
$cream = [System.Drawing.Color]::FromArgb(255, 250, 243, 233)
$bgBrush = New-Object System.Drawing.SolidBrush($terracotta)
$houseBrush = New-Object System.Drawing.SolidBrush($cream)

$g.FillRectangle($bgBrush, 0, 0, $size, $size)

# Chimney first so the roof overlaps its base
$g.FillRectangle($houseBrush, 672, 300, 72, 170)

# Roof
$roof = @(
    (New-Object System.Drawing.PointF(192, 512)),
    (New-Object System.Drawing.PointF(512, 236)),
    (New-Object System.Drawing.PointF(832, 512))
)
$g.FillPolygon($houseBrush, $roof)

# Body
$g.FillRectangle($houseBrush, 288, 512, 448, 288)

# Arched door punched back in background color
$g.FillEllipse($bgBrush, 464, 608, 96, 96)
$g.FillRectangle($bgBrush, 464, 656, 96, 144)

$g.Dispose()
$out = Join-Path $PSScriptRoot "..\Handl\Assets.xcassets\AppIcon.appiconset\icon-1024.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Icon written to $out"

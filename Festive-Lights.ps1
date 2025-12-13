#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

Add-Type -Language CSharp -ReferencedAssemblies @(
    "PresentationCore",
    "PresentationFramework",
    "WindowsBase",
    "System.Xaml"
) -TypeDefinition @"
using System;
using System.Windows;
using System.Windows.Media;

public class VisualHost : FrameworkElement
{
    private Visual _child;

    public VisualHost(Visual child)
    {
        _child = child;
        AddVisualChild(_child);
        AddLogicalChild(_child);
    }

    protected override int VisualChildrenCount
    {
        get { return _child == null ? 0 : 1; }
    }

    protected override Visual GetVisualChild(int index)
    {
        if (_child == null || index != 0) throw new ArgumentOutOfRangeException();
        return _child;
    }
}
"@

function Clamp {
    param([double]$v,[double]$min,[double]$max)
    if ($v -lt $min) { return $min }
    if ($v -gt $max) { return $max }
    $v
}

function ShouldTwinkle {
    param([int]$Chance)
    (Get-Random -Minimum 1 -Maximum ($Chance + 1)) -eq 1
}

function Rand01 {
    (Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0
}

function RandRange {
    param([double]$min,[double]$max)
    $min + ((Rand01) * ($max - $min))
}

$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Width = 900
$window.Height = 700
$window.WindowStartupLocation = "CenterScreen"
$window.SnapsToDevicePixels = $true
$window.UseLayoutRounding = $true

$sceneW = [double]$window.Width
$sceneH = [double]$window.Height

$root = New-Object System.Windows.Controls.Canvas
$root.Width = $sceneW
$root.Height = $sceneH
$window.Content = $root

function New-Layer {
    param([int]$Z,[bool]$Cache)
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = $sceneW
    $c.Height = $sceneH
    if ($Cache) { $c.CacheMode = New-Object System.Windows.Media.BitmapCache }
    [System.Windows.Controls.Canvas]::SetZIndex($c,$Z) | Out-Null
    $root.Children.Add($c) | Out-Null
    $c
}

$bgLayer      = New-Layer 0 $true
$branchLayer  = New-Layer 1 $true
$lightLayer   = New-Layer 2 $false
$snowLayer    = New-Layer 3 $false
$fxLayer      = New-Layer 4 $false
$presentLayer = New-Layer 5 $true

$treeCenterX = $sceneW / 2.0
$treeTopY = 70.0
$treeHeight = 440.0
$treeBaseY = $treeTopY + $treeHeight
$treeMaxHalfWidth = 240.0

function Tree-HalfWidthAtY {
    param([double]$y)
    $t = Clamp (($y - $treeTopY) / $treeHeight) 0 1
    15.0 + (($treeMaxHalfWidth - 15.0) * $t)
}

$sky = New-Object System.Windows.Media.LinearGradientBrush
$sky.StartPoint = New-Object System.Windows.Point(0.5,0.0)
$sky.EndPoint   = New-Object System.Windows.Point(0.5,1.0)
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(8,12,35)),0.0))) | Out-Null
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(18,22,60)),0.55))) | Out-Null
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::Black),1.0))) | Out-Null
$window.Background = $sky

$script:BgStars = @()
$script:BrightStars = @()

function Draw-BackgroundStars {
    param([int]$Count = 200,[int]$BrightCount = 100)
    for ($i=0; $i -lt $Count; $i++) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = (Get-Random -Minimum 1 -Maximum 3)
        $e.Height = $e.Width
        $b = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::White)
        $b.Freeze()
        $e.Fill = $b
        $base = (Get-Random -Minimum 5 -Maximum 60) / 100.0
        $e.Opacity = $base
        [System.Windows.Controls.Canvas]::SetLeft($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneW))) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneH))) | Out-Null
        $bgLayer.Children.Add($e) | Out-Null
        $script:BgStars += @{ Shape = $e; BaseOpacity = $base }
    }
    for ($i=0; $i -lt $BrightCount; $i++) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $sz = (Get-Random -Minimum 2 -Maximum 5)
        $e.Width = $sz
        $e.Height = $sz
        $g = New-Object System.Windows.Media.RadialGradientBrush
        $mid = [System.Windows.Media.Colors]::White
        $mid.A = 160
        $fade = [System.Windows.Media.Colors]::White
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White,0.0))) | Out-Null
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.35))) | Out-Null
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
        $g.Freeze()
        $e.Fill = $g
        $base = (Get-Random -Minimum 55 -Maximum 95) / 100.0
        $e.Opacity = $base
        [System.Windows.Controls.Canvas]::SetLeft($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneW))) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e,(Get-Random -Minimum 0 -Maximum ([int]($sceneH * 0.75)))) | Out-Null
        $bgLayer.Children.Add($e) | Out-Null
        $script:BrightStars += @{ Shape = $e; BaseOpacity = $base }
    }
}

function Draw-TreeBranches {
    $stroke1 = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(10,120,35))
    $stroke2 = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(12,95,30))
    $stroke1.Freeze()
    $stroke2.Freeze()
    for ($l=0; $l -lt 22; $l++) {
        $y = $treeTopY + ($l * ($treeHeight / 22.0))
        $hw = Tree-HalfWidthAtY $y
        for ($b=0; $b -lt 9; $b++) {
            $ln = New-Object System.Windows.Shapes.Line
            $ln.X1 = $treeCenterX
            $ln.Y1 = $y
            $ln.X2 = $treeCenterX + (Get-Random -Minimum (-1 * [int]$hw) -Maximum ([int]$hw))
            $ln.Y2 = $y + (Get-Random -Minimum 10 -Maximum 24)
            $ln.Stroke = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $stroke1 } else { $stroke2 }
            $ln.StrokeThickness = 2
            $ln.Opacity = 0.9
            $branchLayer.Children.Add($ln) | Out-Null
        }
    }
}

function Draw-Presents {
    $palette = @(
        [System.Windows.Media.Colors]::Red,
        [System.Windows.Media.Colors]::Blue,
        [System.Windows.Media.Colors]::Green,
        [System.Windows.Media.Colors]::Magenta,
        [System.Windows.Media.Colors]::Orange,
        [System.Windows.Media.Colors]::Gold
    )
    $baseY = $treeBaseY + 110.0
    $count = 14
    for ($i=0; $i -lt $count; $i++) {
        $w = Get-Random -Minimum 60 -Maximum 140
        $h = Get-Random -Minimum 45 -Maximum 95
        $x = $treeCenterX + (Get-Random -Minimum -260 -Maximum 260)
        $y = $baseY - $h + (Get-Random -Minimum -10 -Maximum 12)
        $col = $palette[(Get-Random -Maximum $palette.Count)]
        $shadow = New-Object System.Windows.Shapes.Rectangle
        $shadow.Width = $w + 10
        $shadow.Height = $h + 10
        $shadow.RadiusX = 10
        $shadow.RadiusY = 10
        $sb = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(70,0,0,0))
        $sb.Freeze()
        $shadow.Fill = $sb
        [System.Windows.Controls.Canvas]::SetLeft($shadow, $x + 6) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($shadow, $y + 6) | Out-Null
        $presentLayer.Children.Add($shadow) | Out-Null
        $box = New-Object System.Windows.Shapes.Rectangle
        $box.Width = $w
        $box.Height = $h
        $box.RadiusX = 8
        $box.RadiusY = 8
        $grad = New-Object System.Windows.Media.LinearGradientBrush
        $grad.StartPoint = New-Object System.Windows.Point(0,0)
        $grad.EndPoint = New-Object System.Windows.Point(1,1)
        $d = $col
        $d.R = [byte](Clamp ($d.R * 0.70) 0 255)
        $d.G = [byte](Clamp ($d.G * 0.70) 0 255)
        $d.B = [byte](Clamp ($d.B * 0.70) 0 255)
        $hcol = $col
        $hcol.R = [byte](Clamp ($hcol.R * 1.05) 0 255)
        $hcol.G = [byte](Clamp ($hcol.G * 1.05) 0 255)
        $hcol.B = [byte](Clamp ($hcol.B * 1.05) 0 255)
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($hcol,0.0))) | Out-Null
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($col,0.35))) | Out-Null
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($d,1.0))) | Out-Null
        $grad.Freeze()
        $box.Fill = $grad
        [System.Windows.Controls.Canvas]::SetLeft($box, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($box, $y) | Out-Null
        $presentLayer.Children.Add($box) | Out-Null
        $shine = New-Object System.Windows.Shapes.Rectangle
        $shine.Width = [Math]::Max(10, $w * 0.22)
        $shine.Height = $h - 8
        $shine.RadiusX = 6
        $shine.RadiusY = 6
        $hb = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(45,255,255,255))
        $hb.Freeze()
        $shine.Fill = $hb
        [System.Windows.Controls.Canvas]::SetLeft($shine, $x + 8) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($shine, $y + 4) | Out-Null
        $presentLayer.Children.Add($shine) | Out-Null
        for ($g=0; $g -lt 28; $g++) {
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 2
            $dot.Height = 2
            $wb = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::White)
            $wb.Freeze()
            $dot.Fill = $wb
            $dot.Opacity = (Get-Random -Minimum 15 -Maximum 80) / 100.0
            [System.Windows.Controls.Canvas]::SetLeft($dot, $x + (Rand01 * $w)) | Out-Null
            [System.Windows.Controls.Canvas]::SetTop($dot, $y + (Rand01 * $h)) | Out-Null
            $presentLayer.Children.Add($dot) | Out-Null
        }
        $rcol = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { [System.Windows.Media.Colors]::Gold } else { [System.Windows.Media.Colors]::White }
        $rb = New-Object System.Windows.Media.SolidColorBrush($rcol)
        $rb.Freeze()
        $off = (Get-Random -Minimum -12 -Maximum 13)
        $centerX = $x + ($w / 2.0) + $off
        $ribV = New-Object System.Windows.Shapes.Rectangle
        $ribV.Width = 10
        $ribV.Height = $h
        $ribV.Fill = $rb
        [System.Windows.Controls.Canvas]::SetLeft($ribV, $centerX - 5.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribV, $y) | Out-Null
        $presentLayer.Children.Add($ribV) | Out-Null
        $ribH = New-Object System.Windows.Shapes.Rectangle
        $ribH.Width = $w
        $ribH.Height = 10
        $ribH.Fill = $rb
        [System.Windows.Controls.Canvas]::SetLeft($ribH, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribH, ($y + ($h / 2.0) - 5.0)) | Out-Null
        $presentLayer.Children.Add($ribH) | Out-Null
        $bowY = $y - 6.0
        $knot = New-Object System.Windows.Shapes.Ellipse
        $knot.Width = 8
        $knot.Height = 8
        $knot.Fill = $rb
        [System.Windows.Controls.Canvas]::SetLeft($knot, $centerX - 4.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($knot, $bowY) | Out-Null
        $presentLayer.Children.Add($knot) | Out-Null
        $bowL = New-Object System.Windows.Shapes.Polygon
        $bowL.Fill = $rb
        $pcl = New-Object System.Windows.Media.PointCollection
        $pcl.Add((New-Object System.Windows.Point($centerX, $bowY + 4))) | Out-Null
        $pcl.Add((New-Object System.Windows.Point($centerX - 18, $bowY - 10))) | Out-Null
        $pcl.Add((New-Object System.Windows.Point($centerX - 6, $bowY + 2))) | Out-Null
        $bowL.Points = $pcl
        $presentLayer.Children.Add($bowL) | Out-Null
        $bowR = New-Object System.Windows.Shapes.Polygon
        $bowR.Fill = $rb
        $pcr = New-Object System.Windows.Media.PointCollection
        $pcr.Add((New-Object System.Windows.Point($centerX, $bowY + 4))) | Out-Null
        $pcr.Add((New-Object System.Windows.Point($centerX + 18, $bowY - 10))) | Out-Null
        $pcr.Add((New-Object System.Windows.Point($centerX + 6, $bowY + 2))) | Out-Null
        $bowR.Points = $pcr
        $presentLayer.Children.Add($bowR) | Out-Null
    }
}

$lightPalette = @(
    [System.Windows.Media.Colors]::Red,
    [System.Windows.Media.Colors]::Yellow,
    [System.Windows.Media.Colors]::DeepSkyBlue,
    [System.Windows.Media.Colors]::Lime,
    [System.Windows.Media.Colors]::Magenta,
    [System.Windows.Media.Colors]::Cyan,
    [System.Windows.Media.Colors]::Orange
)

$script:LightCoreBrushes = @()
$script:LightGlowBrushes = @()

foreach ($c in $lightPalette) {
    $core = New-Object System.Windows.Media.SolidColorBrush($c)
    $core.Freeze()
    $script:LightCoreBrushes += $core
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.Center = New-Object System.Windows.Point(0.5,0.5)
    $g.GradientOrigin = New-Object System.Windows.Point(0.5,0.5)
    $g.RadiusX = 0.5
    $g.RadiusY = 0.5
    $mid = $c
    $mid.A = 120
    $fade = $c
    $fade.A = 0
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c,0.0))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.40))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
    $g.Freeze()
    $script:LightGlowBrushes += $g
}

$script:LightParticles = @()
$script:LightsVisual = New-Object System.Windows.Media.DrawingVisual
$script:LightsHost = New-Object VisualHost($script:LightsVisual)
$lightLayer.Children.Add($script:LightsHost) | Out-Null

function Init-Lights {
    param([int]$Count = 400)
    $script:LightParticles = @()
    for ($i=0; $i -lt $Count; $i++) {
        $y = $treeTopY + (Rand01 * $treeHeight)
        $hw = Tree-HalfWidthAtY $y
        $x = $treeCenterX + (RandRange (-1.0 * $hw) $hw)
        $script:LightParticles += @{ X=[double]$x; Y=[double]$y; CI=(Get-Random -Maximum $script:LightGlowBrushes.Count); CO=0.85; BaseGO=(0.70 + (Rand01/6.0)); GO=0.70 }
    }
}

function Render-Lights {
    param([int]$Frame)
    $dc = $script:LightsVisual.RenderOpen()
    $doOpacity = (($Frame % 2) -eq 0)
    foreach ($l in $script:LightParticles) {
        if (ShouldTwinkle 3) { $l.CI = Get-Random -Maximum $script:LightGlowBrushes.Count }
        if ($doOpacity) {
            $l.GO = Clamp ($l.BaseGO + ((Get-Random -Minimum -10 -Maximum 11)/100.0)) 0.30 1.00
            $l.CO = Clamp (0.78 + ((Get-Random -Minimum -6 -Maximum 7)/100.0)) 0.65 1.00
        }
        $pt = New-Object System.Windows.Point($l.X,$l.Y)
        $dc.PushOpacity($l.GO)
        $dc.DrawEllipse($script:LightGlowBrushes[$l.CI], $null, $pt, 9.0, 9.0)
        $dc.Pop()
        $dc.PushOpacity($l.CO)
        $dc.DrawEllipse($script:LightCoreBrushes[$l.CI], $null, $pt, 3.5, 3.5)
        $dc.Pop()
    }
    $dc.Close()
}

$script:SnowParticles = @()
$script:SnowVisual = New-Object System.Windows.Media.DrawingVisual
$script:SnowHost = New-Object VisualHost($script:SnowVisual)
$snowLayer.Children.Add($script:SnowHost) | Out-Null

$script:SnowGlowBrush = $null
$script:SnowCoreBrush = $null

function Init-SnowBrushes {
    $cg = [System.Windows.Media.Colors]::White
    $mid = $cg
    $mid.A = 110
    $fade = $cg
    $fade.A = 0
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($cg,0.0))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.35))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
    $g.Freeze()
    $script:SnowGlowBrush = $g
    $b = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::White)
    $b.Freeze()
    $script:SnowCoreBrush = $b
}

function Init-Snow {
    param([int]$Count = 120)
    $script:SnowParticles = @()
    for ($i=0; $i -lt $Count; $i++) {
        $size = Get-Random -Minimum 2 -Maximum 7
        $script:SnowParticles += @{
            X = (Rand01 * $sceneW)
            Y = (Rand01 * $sceneH)
            VX = ((Get-Random -Minimum -30 -Maximum 31) / 100.0)
            VY = (0.7 + (Rand01 / 1.3)) * (1.0 + ($size / 12.0))
            S = [double]$size
            O = 0.22 + (Rand01 / 4.0)
            BaseO = 0.22 + (Rand01 / 6.0)
        }
    }
}

function Render-Snow {
    $dc = $script:SnowVisual.RenderOpen()
    foreach ($s in $script:SnowParticles) {
        $s.X = $s.X + $s.VX
        $s.Y = $s.Y + $s.VY
        if ($s.X -gt ($sceneW + 20)) { $s.X = -20 }
        if ($s.X -lt -20) { $s.X = $sceneW + 20 }
        if ($s.Y -gt ($sceneH + 30)) { $s.Y = -30; $s.X = (Rand01 * $sceneW) }
        if (ShouldTwinkle 35) { $s.O = Clamp ($s.BaseO + ((Get-Random -Minimum -10 -Maximum 11)/100.0)) 0.12 0.60 }
        $pt = New-Object System.Windows.Point($s.X,$s.Y)
        $dc.PushOpacity($s.O)
        $dc.DrawEllipse($script:SnowGlowBrush, $null, $pt, ($s.S * 1.5), ($s.S * 1.5))
        $dc.Pop()
        $dc.PushOpacity(0.62)
        $dc.DrawEllipse($script:SnowCoreBrush, $null, $pt, ($s.S * 0.5), ($s.S * 0.5))
        $dc.Pop()
    }
    $dc.Close()
}

$script:ShootingStars = @()
$script:NextShootAt = 0
$script:ShootVisual = New-Object System.Windows.Media.DrawingVisual
$script:ShootHost = New-Object VisualHost($script:ShootVisual)
$fxLayer.Children.Add($script:ShootHost) | Out-Null

$script:ShootCorePen = $null
$script:ShootGlowPen = $null

function Init-ShootingPens {
    $wb = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Colors]::White)
    $wb.Freeze()
    $p1 = New-Object System.Windows.Media.Pen($wb,2.0)
    $p1.StartLineCap = [System.Windows.Media.PenLineCap]::Round
    $p1.EndLineCap = [System.Windows.Media.PenLineCap]::Round
    $p1.Freeze()
    $p2 = New-Object System.Windows.Media.Pen($wb,6.0)
    $p2.StartLineCap = [System.Windows.Media.PenLineCap]::Round
    $p2.EndLineCap = [System.Windows.Media.PenLineCap]::Round
    $p2.Freeze()
    $script:ShootCorePen = $p1
    $script:ShootGlowPen = $p2
}

function New-ShootingStar {
    $x = (Get-Random -Minimum -200 -Maximum ([int]$sceneW)) * 1.0
    $y = (Get-Random -Minimum 30 -Maximum 240) * 1.0
    $vx = 14.0 + ((Get-Random -Minimum 0 -Maximum 90) / 10.0)
    $vy = 3.0 + ((Get-Random -Minimum 0 -Maximum 60) / 10.0)
    $maxLife = Get-Random -Minimum 35 -Maximum 80
    $len = 55.0 + (Get-Random -Minimum 0 -Maximum 30)
    @{ X=$x; Y=$y; VX=$vx; VY=$vy; Life=0; MaxLife=$maxLife; Len=$len }
}

function Maybe-LaunchShootingStars {
    if ($script:NextShootAt -le 0) { $script:NextShootAt = Get-Random -Minimum 80 -Maximum 220; return }
    $script:NextShootAt--
    if ($script:NextShootAt -eq 0) {
        $n = Get-Random -Minimum 1 -Maximum 3
        for ($i=0; $i -lt $n; $i++) { $script:ShootingStars += (New-ShootingStar) }
    }
}

function Update-ShootingStars {
    $alive = @()
    foreach ($st in $script:ShootingStars) {
        $st.Life++
        $st.X += $st.VX
        $st.Y += $st.VY
        if ($st.Life -lt $st.MaxLife -and $st.X -lt ($sceneW + 250) -and $st.Y -lt ($sceneH + 250)) { $alive += $st }
    }
    $script:ShootingStars = $alive
}

function Render-ShootingStars {
    $dc = $script:ShootVisual.RenderOpen()
    foreach ($st in $script:ShootingStars) {
        $fade = Clamp (1.0 - ($st.Life / [double]$st.MaxLife)) 0 1
        $x2 = $st.X
        $y2 = $st.Y
        $x1 = $st.X - $st.Len
        $y1 = $st.Y - ($st.Len * 0.25)
        $p1 = New-Object System.Windows.Point($x1,$y1)
        $p2 = New-Object System.Windows.Point($x2,$y2)
        $dc.PushOpacity(0.30 * $fade)
        $dc.DrawLine($script:ShootGlowPen,$p1,$p2)
        $dc.Pop()
        $dc.PushOpacity(0.85 * $fade)
        $dc.DrawLine($script:ShootCorePen,$p1,$p2)
        $dc.Pop()
    }
    $dc.Close()
}

$script:frame = 0

function Update-Scene {
    $script:frame++
    Render-Lights -Frame $script:frame
    Render-Snow
    Maybe-LaunchShootingStars
    Update-ShootingStars
    Render-ShootingStars
    if (ShouldTwinkle 25 -and $script:BgStars.Count -gt 0) {
        $idx = Get-Random -Maximum $script:BgStars.Count
        $s = $script:BgStars[$idx]
        $s.Shape.Opacity = Clamp ($s.BaseOpacity + ((Get-Random -Minimum -30 -Maximum 31)/100.0)) 0.05 1.0
    }
    if (ShouldTwinkle 20 -and $script:BrightStars.Count -gt 0) {
        $idx2 = Get-Random -Maximum $script:BrightStars.Count
        $s2 = $script:BrightStars[$idx2]
        $s2.Shape.Opacity = Clamp ($s2.BaseOpacity + ((Get-Random -Minimum -20 -Maximum 21)/100.0)) 0.25 1.0
    }
}

Draw-BackgroundStars -Count 200 -BrightCount 100
Draw-TreeBranches
Draw-Presents
Init-Lights -Count 400
Init-SnowBrushes
Init-Snow -Count 120
Init-ShootingPens

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({ Update-Scene })
$timer.Start()

$app = [System.Windows.Application]::Current
if (-not $app) {
    $app = New-Object System.Windows.Application
    [void]$app.Run($window)
} else {
    [void]$window.ShowDialog()
}

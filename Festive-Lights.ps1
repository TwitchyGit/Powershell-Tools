#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

##################################################
# Window
##################################################
$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Width = 900
$window.Height = 700
$window.WindowStartupLocation = "CenterScreen"
$window.SnapsToDevicePixels = $true
$window.UseLayoutRounding = $true

$sceneW = [double]$window.Width
$sceneH = [double]$window.Height

##################################################
# Root + layered canvases
##################################################
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
$presentLayer = New-Layer 4 $true

##################################################
# Helpers
##################################################
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

##################################################
# Scene parameters
##################################################
$treeCenterX = $sceneW / 2
$treeTopY = 70
$treeHeight = 440
$treeBaseY = $treeTopY + $treeHeight
$treeMaxHalfWidth = 240

function Tree-HalfWidthAtY {
    param([double]$y)
    $t = Clamp (($y - $treeTopY) / $treeHeight) 0 1
    15 + (($treeMaxHalfWidth - 15) * $t)
}

##################################################
# Sky background
##################################################
$sky = New-Object System.Windows.Media.LinearGradientBrush
$sky.StartPoint = "0.5,0"
$sky.EndPoint   = "0.5,1"
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([Windows.Media.Color]::FromRgb(8,12,35)),0)))
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([Windows.Media.Color]::FromRgb(18,22,60)),0.55)))
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([Windows.Media.Colors]::Black),1)))
$window.Background = $sky

##################################################
# Background stars (cached)
##################################################
$script:BgStars = @()
function Draw-BackgroundStars {
    for ($i=0;$i -lt 250;$i++) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = (Get-Random -Minimum 1 -Maximum 3)
        $e.Height = $e.Width
        $b = New-Object System.Windows.Media.SolidColorBrush([Windows.Media.Colors]::White)
        $b.Freeze()
        $e.Fill = $b
        $e.Opacity = (Get-Random -Minimum 5 -Maximum 60)/100
        [Canvas]::SetLeft($e,(Get-Random*$sceneW))
        [Canvas]::SetTop($e,(Get-Random*$sceneH))
        $bgLayer.Children.Add($e) | Out-Null
        $script:BgStars += @{Shape=$e;Base=$e.Opacity}
    }
}

##################################################
# Tree branches (cached)
##################################################
function Draw-Tree {
    $stroke1 = New-Object System.Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(10,120,35))
    $stroke2 = New-Object System.Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(12,95,30))
    $stroke1.Freeze(); $stroke2.Freeze()

    for ($l=0;$l -lt 22;$l++) {
        $y = $treeTopY + ($l*($treeHeight/22))
        $hw = Tree-HalfWidthAtY $y
        for ($b=0;$b -lt 9;$b++) {
            $ln = New-Object System.Windows.Shapes.Line
            $ln.X1 = $treeCenterX
            $ln.Y1 = $y
            $ln.X2 = $treeCenterX + (Get-Random -Minimum (-$hw) -Maximum $hw)
            $ln.Y2 = $y + (Get-Random -Minimum 10 -Maximum 24)
            $ln.Stroke = if ((Get-Random%2)-eq 0){$stroke1}else{$stroke2}
            $ln.StrokeThickness = 2
            $ln.Opacity = 0.9
            $branchLayer.Children.Add($ln) | Out-Null
        }
    }
}

##################################################
# Cached light brushes
##################################################
$lightPalette = @(
    [Windows.Media.Colors]::Red,
    [Windows.Media.Colors]::Yellow,
    [Windows.Media.Colors]::DeepSkyBlue,
    [Windows.Media.Colors]::Lime,
    [Windows.Media.Colors]::Magenta,
    [Windows.Media.Colors]::Cyan,
    [Windows.Media.Colors]::Orange
)

$script:LightCoreBrushes = @()
$script:LightGlowBrushes = @()

foreach ($c in $lightPalette) {
    $core = New-Object Windows.Media.SolidColorBrush($c)
    $core.Freeze()
    $script:LightCoreBrushes += $core

    $g = New-Object Windows.Media.RadialGradientBrush
    $mid = $c; $mid.A = 120
    $fade = $c; $fade.A = 0
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop($c,0)))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop($mid,0.4)))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop($fade,1)))
    $g.Freeze()
    $script:LightGlowBrushes += $g
}

##################################################
# Lights via DrawingVisual
##################################################
$script:LightParticles = @()
$script:LightsVisual = New-Object System.Windows.Media.DrawingVisual
$lightLayer.Children.Add($script:LightsVisual)

function Init-Lights {
    for ($i=0;$i -lt 400;$i++) {
        $y = $treeTopY + (Get-Random*$treeHeight)
        $hw = Tree-HalfWidthAtY $y
        $script:LightParticles += @{
            X=$treeCenterX + (Get-Random -Minimum (-$hw) -Maximum $hw)
            Y=$y
            CI=Get-Random -Maximum $script:LightGlowBrushes.Count
            GO=0.6+(Get-Random/3)
            CO=0.85
        }
    }
}

function Render-Lights {
    $dc = $script:LightsVisual.RenderOpen()
    foreach ($l in $script:LightParticles) {
        if (ShouldTwinkle 3) { $l.CI = Get-Random -Maximum $script:LightGlowBrushes.Count }
        if (($script:frame%2)-eq 0) {
            $l.GO = Clamp ($l.GO + ((Get-Random-10)/100)) 0.3 1
            $l.CO = Clamp ($l.CO + ((Get-Random-6)/100)) 0.65 1
        }
        $dc.PushOpacity($l.GO)
        $dc.DrawEllipse($script:LightGlowBrushes[$l.CI],$null,(New-Object Windows.Point($l.X,$l.Y)),9,9)
        $dc.Pop()
        $dc.PushOpacity($l.CO)
        $dc.DrawEllipse($script:LightCoreBrushes[$l.CI],$null,(New-Object Windows.Point($l.X,$l.Y)),3.5,3.5)
        $dc.Pop()
    }
    $dc.Close()
}

##################################################
# Snow via DrawingVisual
##################################################
$script:SnowParticles = @()
$script:SnowVisual = New-Object System.Windows.Media.DrawingVisual
$snowLayer.Children.Add($script:SnowVisual)

function Init-Snow {
    for ($i=0;$i -lt 120;$i++) {
        $script:SnowParticles += @{
            X=Get-Random*$sceneW
            Y=Get-Random*$sceneH
            VX=(Get-Random-30)/100
            VY=0.7+(Get-Random/1.3)
            S=Get-Random -Minimum 2 -Maximum 6
            O=0.25+(Get-Random/4)
        }
    }
}

function Render-Snow {
    $dc = $script:SnowVisual.RenderOpen()
    foreach ($s in $script:SnowParticles) {
        $s.X += $s.VX; $s.Y += $s.VY
        if ($s.Y -gt $sceneH+20){$s.Y=-20;$s.X=Get-Random*$sceneW}
        $dc.PushOpacity($s.O)
        $dc.DrawEllipse([Windows.Media.Brushes]::White,$null,(New-Object Windows.Point($s.X,$s.Y)),$s.S*1.5,$s.S*1.5)
        $dc.Pop()
        $dc.DrawEllipse([Windows.Media.Brushes]::White,$null,(New-Object Windows.Point($s.X,$s.Y)),$s.S/2,$s.S/2)
    }
    $dc.Close()
}

##################################################
# Presents (cached)
##################################################
function Draw-Presents {
    for ($i=0;$i -lt 12;$i++) {
        $w=Get-Random -Minimum 60 -Maximum 130
        $h=Get-Random -Minimum 45 -Maximum 95
        $x=$treeCenterX+(Get-Random -Minimum -260 -Maximum 260)
        $y=$treeBaseY+110-$h
        $r=New-Object Windows.Shapes.Rectangle
        $r.Width=$w;$r.Height=$h;$r.RadiusX=8;$r.RadiusY=8
        $c=$lightPalette[(Get-Random -Maximum $lightPalette.Count)]
        $b=New-Object Windows.Media.LinearGradientBrush
        $b.GradientStops.Add((New-Object Windows.Media.GradientStop($c,0)))
        $d=$c;$d.R=[byte]($d.R*0.7)
        $b.GradientStops.Add((New-Object Windows.Media.GradientStop($d,1)))
        $r.Fill=$b
        [Canvas]::SetLeft($r,$x);[Canvas]::SetTop($r,$y)
        $presentLayer.Children.Add($r)|Out-Null
    }
}

##################################################
# Animation
##################################################
$script:frame=0
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({
    $script:frame++
    Render-Lights
    Render-Snow
})

##################################################
# Build
##################################################
Draw-BackgroundStars
Draw-Tree
Init-Lights
Init-Snow
Draw-Presents
$timer.Start()

##################################################
# Run safely
##################################################
$app=[Windows.Application]::Current
if(-not $app){$app=New-Object Windows.Application;[void]$app.Run($window)}else{[void]$window.ShowDialog()}

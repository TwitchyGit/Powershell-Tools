#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

##################################################
# Window, canvas
##################################################
$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Width = 900
$window.Height = 700
$window.Background = [System.Windows.Media.Brushes]::Black
$window.WindowStartupLocation = "CenterScreen"

$canvas = New-Object System.Windows.Controls.Canvas
$canvas.Width = $window.Width
$canvas.Height = $window.Height
$window.Content = $canvas

##################################################
# Helpers
##################################################
function New-SolidBrush {
    param([System.Windows.Media.Color]$Color)
    $b = New-Object System.Windows.Media.SolidColorBrush($Color)
    $b.Freeze()
    $b
}

function New-RadialGlowBrush {
    param(
        [System.Windows.Media.Color]$Color,
        [double]$CoreStop = 0.0,
        [double]$MidStop = 0.35,
        [double]$EdgeStop = 1.0
    )
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.GradientOrigin = New-Object System.Windows.Point(0.5,0.5)
    $g.Center = New-Object System.Windows.Point(0.5,0.5)
    $g.RadiusX = 0.5
    $g.RadiusY = 0.5

    $c1 = $Color
    $c2 = $Color
    $c3 = $Color
    $c2.A = 120
    $c3.A = 0

    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c1,$CoreStop))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c2,$MidStop)))  | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c3,$EdgeStop))) | Out-Null
    $g
}

function ShouldTwinkle {
    param([int]$TwinkleChance = 7)
    (Get-Random -Minimum 1 -Maximum ($TwinkleChance + 1)) -eq 1
}

function Clamp {
    param([double]$v,[double]$min,[double]$max)
    if ($v -lt $min) { return $min }
    if ($v -gt $max) { return $max }
    $v
}

##################################################
# Scene parameters
##################################################
$sceneW = [double]$window.Width
$sceneH = [double]$window.Height

$treeCenterX = $sceneW / 2
$treeTopY = 70
$treeHeight = 440
$treeBaseY = $treeTopY + $treeHeight
$treeMaxHalfWidth = 240

$trunkHeight = 75
$trunkWidth = 50

$branchStroke = New-SolidBrush ([System.Windows.Media.Color]::FromRgb(10,120,35))
$branchStroke2 = New-SolidBrush ([System.Windows.Media.Color]::FromRgb(12,95,30))
$trunkBrush = New-SolidBrush ([System.Windows.Media.Color]::FromRgb(120,70,25))

$lightPalette = @(
    [System.Windows.Media.Colors]::Red,
    [System.Windows.Media.Colors]::Yellow,
    [System.Windows.Media.Colors]::DeepSkyBlue,
    [System.Windows.Media.Colors]::Lime,
    [System.Windows.Media.Colors]::Magenta,
    [System.Windows.Media.Colors]::Cyan,
    [System.Windows.Media.Colors]::Orange
)

$bgStarPalette = @(
    [System.Windows.Media.Colors]::White,
    [System.Windows.Media.Colors]::Gainsboro,
    [System.Windows.Media.Colors]::LightGray,
    [System.Windows.Media.Colors]::Silver
)

$starSegmentColors = @(
    [System.Windows.Media.Colors]::Gold,
    [System.Windows.Media.Colors]::Yellow,
    [System.Windows.Media.Colors]::Orange,
    [System.Windows.Media.Colors]::HotPink,
    [System.Windows.Media.Colors]::Cyan
)

##################################################
# Storage
##################################################
$script:BranchShapes = @()
$script:LightObjs = @()   # each: @{Glow=Ellipse; Core=Ellipse; ColorIndex=int; BaseOpacity=double}
$script:BgStars = @()     # each: @{Shape=Ellipse; BaseOpacity=double}
$script:StarSegments = @()# each: @{Shape=Polygon; BaseOpacity=double}
$script:Presents = @()
$script:frame = 0

##################################################
# Geometry helpers
##################################################
function Tree-HalfWidthAtY {
    param([double]$y)
    $t = ($y - $treeTopY) / $treeHeight
    $t = Clamp $t 0 1
    (15 + ($treeMaxHalfWidth - 15) * $t)
}

function Is-InTreeCone {
    param([double]$x,[double]$y)
    if ($y -lt $treeTopY) { return $false }
    if ($y -gt $treeBaseY) { return $false }
    $hw = Tree-HalfWidthAtY $y
    ($x -ge ($treeCenterX - $hw)) -and ($x -le ($treeCenterX + $hw))
}

##################################################
# Draw background stars
##################################################
function Draw-BackgroundStars {
    param([int]$Count = 200)

    for ($i=0; $i -lt $Count; $i++) {
        $x = Get-Random -Minimum 0 -Maximum ([int]$sceneW)
        $y = Get-Random -Minimum 0 -Maximum ([int]$sceneH)

        if (Is-InTreeCone $x $y) { continue }

        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = (Get-Random -Minimum 1 -Maximum 3)
        $e.Height = $e.Width
        $c = $bgStarPalette[(Get-Random -Maximum $bgStarPalette.Count)]
        $e.Fill = New-SolidBrush $c
        $base = (Get-Random -Minimum 15 -Maximum 85) / 100.0
        $e.Opacity = $base

        [System.Windows.Controls.Canvas]::SetLeft($e, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e, $y) | Out-Null
        $canvas.Children.Add($e) | Out-Null

        $script:BgStars += @{ Shape = $e; BaseOpacity = $base }
    }
}

##################################################
# Draw tree branches (no solid fill)
##################################################
function Draw-TreeBranches {
    $layers = 22
    $layerStep = $treeHeight / $layers

    for ($li=0; $li -lt $layers; $li++) {
        $y = $treeTopY + ($li * $layerStep)
        $hw = Tree-HalfWidthAtY ($y + ($layerStep * 0.8))

        $primaryCount = 10
        for ($p=0; $p -lt $primaryCount; $p++) {
            $jitterY = (Get-Random -Minimum -6 -Maximum 7)
            $yy = $y + $jitterY + (Get-Random -Minimum 0 -Maximum ([int]($layerStep * 0.9)))

            $span = $hw * (0.65 + ((Get-Random -Minimum 0 -Maximum 35) / 100.0))
            $span = Clamp $span 25 $hw

            $startX = $treeCenterX + (Get-Random -Minimum -6 -Maximum 7)
            $startY = $yy

            $dir = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
            $endX = $startX + ($dir * $span)
            $endY = $startY + (Get-Random -Minimum -8 -Maximum 10)

            $pl = New-Object System.Windows.Shapes.Polyline
            $pl.Stroke = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $branchStroke } else { $branchStroke2 }
            $pl.StrokeThickness = 2.0
            $pl.StrokeStartLineCap = "Round"
            $pl.StrokeEndLineCap = "Round"
            $pl.StrokeLineJoin = "Round"
            $pl.Opacity = 0.95

            $pts = New-Object System.Windows.Media.PointCollection
            $pts.Add((New-Object System.Windows.Point($startX,$startY))) | Out-Null

            $segments = 4 + (Get-Random -Minimum 0 -Maximum 3)
            for ($s=1; $s -le $segments; $s++) {
                $t = $s / $segments
                $xx = $startX + (($endX - $startX) * $t) + (Get-Random -Minimum -6 -Maximum 7)
                $yyy = $startY + (($endY - $startY) * $t) + (Get-Random -Minimum -4 -Maximum 5)
                $pts.Add((New-Object System.Windows.Point($xx,$yyy))) | Out-Null
            }

            $pl.Points = $pts
            $canvas.Children.Add($pl) | Out-Null
            $script:BranchShapes += $pl

            $secCount = 2 + (Get-Random -Minimum 0 -Maximum 3)
            for ($sc=0; $sc -lt $secCount; $sc++) {
                $attachIdx = Get-Random -Minimum 1 -Maximum ($pts.Count - 1)
                $ax = $pts[$attachIdx].X
                $ay = $pts[$attachIdx].Y

                $secLen = ($span * (0.18 + ((Get-Random -Minimum 0 -Maximum 20)/100.0)))
                $secDir = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { -1 } else { 1 }
                $sx2 = $ax + ($secDir * $secLen)
                $sy2 = $ay + (Get-Random -Minimum -10 -Maximum 12)

                $ln = New-Object System.Windows.Shapes.Line
                $ln.X1 = $ax
                $ln.Y1 = $ay
                $ln.X2 = $sx2
                $ln.Y2 = $sy2
                $ln.Stroke = $pl.Stroke
                $ln.StrokeThickness = 1.4
                $ln.StrokeStartLineCap = "Round"
                $ln.StrokeEndLineCap = "Round"
                $ln.Opacity = 0.85

                $canvas.Children.Add($ln) | Out-Null
                $script:BranchShapes += $ln
            }
        }
    }

    $trunk = New-Object System.Windows.Shapes.Rectangle
    $trunk.Width = $trunkWidth
    $trunk.Height = $trunkHeight
    $trunk.Fill = $trunkBrush
    $trunk.RadiusX = 6
    $trunk.RadiusY = 6
    [System.Windows.Controls.Canvas]::SetLeft($trunk, $treeCenterX - ($trunkWidth/2)) | Out-Null
    [System.Windows.Controls.Canvas]::SetTop($trunk, $treeBaseY - 5) | Out-Null
    $canvas.Children.Add($trunk) | Out-Null
}

##################################################
# Lights (400) with glow
##################################################
function New-LightObject {
    param([double]$x,[double]$y,[System.Windows.Media.Color]$color)

    $glow = New-Object System.Windows.Shapes.Ellipse
    $glow.Width = 18
    $glow.Height = 18
    $glow.Fill = New-RadialGlowBrush $color
    $glow.Opacity = 0.95
    [System.Windows.Controls.Canvas]::SetLeft($glow, $x - 9) | Out-Null
    [System.Windows.Controls.Canvas]::SetTop($glow, $y - 9) | Out-Null

    $core = New-Object System.Windows.Shapes.Ellipse
    $core.Width = 7
    $core.Height = 7
    $core.Fill = New-SolidBrush $color
    $core.Opacity = 1.0
    [System.Windows.Controls.Canvas]::SetLeft($core, $x - 3.5) | Out-Null
    [System.Windows.Controls.Canvas]::SetTop($core, $y - 3.5) | Out-Null

    $canvas.Children.Add($glow) | Out-Null
    $canvas.Children.Add($core) | Out-Null

    @{
        Glow = $glow
        Core = $core
        BaseOpacity = 0.85 + ((Get-Random -Minimum 0 -Maximum 15) / 100.0)
        ColorIndex = -1
    }
}

function Draw-Lights {
    param([int]$Count = 400)

    $script:LightObjs = @()

    for ($i=0; $i -lt $Count; $i++) {
        $t = ($i + 0.5) / $Count
        $y = $treeTopY + ($treeHeight * $t) + (Get-Random -Minimum -6 -Maximum 7)
        $hw = Tree-HalfWidthAtY $y

        $x = $treeCenterX + (Get-Random -Minimum (-1 * [int]$hw) -Maximum ([int]$hw))
        if (-not (Is-InTreeCone $x $y)) { $i--; continue }

        $ci = Get-Random -Maximum $lightPalette.Count
        $c = $lightPalette[$ci]
        $o = New-LightObject -x $x -y $y -color $c
        $o.ColorIndex = $ci

        $script:LightObjs += $o
    }
}

##################################################
# Multicolour 5 point star with twinkle
##################################################
function Draw-TopStar {
    $cx = $treeCenterX
    $cy = $treeTopY - 18

    $outerR = 26
    $innerR = 12

    $points = @()
    for ($i=0; $i -lt 10; $i++) {
        $ang = (-90 + ($i * 36)) * [Math]::PI / 180.0
        $r = if (($i % 2) -eq 0) { $outerR } else { $innerR }
        $px = $cx + ($r * [Math]::Cos($ang))
        $py = $cy + ($r * [Math]::Sin($ang))
        $points += ,(New-Object System.Windows.Point($px,$py))
    }

    $script:StarSegments = @()
    for ($k=0; $k -lt 5; $k++) {
        $p1 = $points[$k*2]
        $p2 = $points[(($k*2)+1) % 10]
        $p3 = $points[(($k*2)+2) % 10]

        $poly = New-Object System.Windows.Shapes.Polygon
        $pc = New-Object System.Windows.Media.PointCollection
        $pc.Add((New-Object System.Windows.Point($cx,$cy))) | Out-Null
        $pc.Add($p2) | Out-Null
        $pc.Add($p1) | Out-Null
        $pc.Add($p3) | Out-Null
        $poly.Points = $pc

        $col = $starSegmentColors[$k]
        $poly.Fill = New-SolidBrush $col
        $poly.Stroke = New-SolidBrush ([System.Windows.Media.Colors]::White)
        $poly.StrokeThickness = 1.0
        $poly.Opacity = 0.95

        $canvas.Children.Add($poly) | Out-Null
        $script:StarSegments += @{ Shape = $poly; BaseOpacity = 0.85 + ((Get-Random -Minimum 0 -Maximum 10)/100.0) }
    }

    $gl = New-Object System.Windows.Shapes.Ellipse
    $gl.Width = 80
    $gl.Height = 80
    $gl.Fill = New-RadialGlowBrush ([System.Windows.Media.Colors]::Gold)
    $gl.Opacity = 0.55
    [System.Windows.Controls.Canvas]::SetLeft($gl, $cx - 40) | Out-Null
    [System.Windows.Controls.Canvas]::SetTop($gl, $cy - 40) | Out-Null
    $canvas.Children.Insert(0,$gl) | Out-Null
}

##################################################
# Presents (minimum 4) with ribbons and bows
##################################################
function Draw-Presents {
    $baseY = $treeBaseY + $trunkHeight - 5
    $startX = $treeCenterX - 210

    $presentSpecs = @(
        @{ Fill = [System.Windows.Media.Colors]::Red;      X = $startX + 0;   W = 90; H = 65 },
        @{ Fill = [System.Windows.Media.Colors]::Blue;     X = $startX + 105; W = 85; H = 58 },
        @{ Fill = [System.Windows.Media.Colors]::Green;    X = $startX + 205; W = 95; H = 70 },
        @{ Fill = [System.Windows.Media.Colors]::Magenta;  X = $startX + 320; W = 80; H = 60 }
    )

    foreach ($p in $presentSpecs) {
        $box = New-Object System.Windows.Shapes.Rectangle
        $box.Width = $p.W
        $box.Height = $p.H
        $box.RadiusX = 6
        $box.RadiusY = 6
        $box.Fill = New-SolidBrush $p.Fill
        $box.Stroke = New-SolidBrush ([System.Windows.Media.Colors]::Black)
        $box.StrokeThickness = 1.0

        [System.Windows.Controls.Canvas]::SetLeft($box, $p.X) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($box, $baseY - $p.H) | Out-Null
        $canvas.Children.Add($box) | Out-Null

        $rcol = [System.Windows.Media.Colors]::Gold
        if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $rcol = [System.Windows.Media.Colors]::White }

        $ribV = New-Object System.Windows.Shapes.Rectangle
        $ribV.Width = 10
        $ribV.Height = $p.H
        $ribV.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribV, $p.X + ($p.W/2) - 5) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribV, $baseY - $p.H) | Out-Null
        $canvas.Children.Add($ribV) | Out-Null

        $ribH = New-Object System.Windows.Shapes.Rectangle
        $ribH.Width = $p.W
        $ribH.Height = 10
        $ribH.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribH, $p.X) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribH, $baseY - ($p.H/2) - 5) | Out-Null
        $canvas.Children.Add($ribH) | Out-Null

        $bowLeft = New-Object System.Windows.Shapes.Polygon
        $bowLeft.Fill = New-SolidBrush $rcol
        $bowLeftPts = New-Object System.Windows.Media.PointCollection
        $bx = $p.X + ($p.W/2)
        $by = ($baseY - $p.H) - 4
        $bowLeftPts.Add((New-Object System.Windows.Point($bx,$by))) | Out-Null
        $bowLeftPts.Add((New-Object System.Windows.Point($bx-18,$by-12))) | Out-Null
        $bowLeftPts.Add((New-Object System.Windows.Point($bx-6,$by-2))) | Out-Null
        $bowLeft.Points = $bowLeftPts
        $canvas.Children.Add($bowLeft) | Out-Null

        $bowRight = New-Object System.Windows.Shapes.Polygon
        $bowRight.Fill = New-SolidBrush $rcol
        $bowRightPts = New-Object System.Windows.Media.PointCollection
        $bowRightPts.Add((New-Object System.Windows.Point($bx,$by))) | Out-Null
        $bowRightPts.Add((New-Object System.Windows.Point($bx+18,$by-12))) | Out-Null
        $bowRightPts.Add((New-Object System.Windows.Point($bx+6,$by-2))) | Out-Null
        $bowRight.Points = $bowRightPts
        $canvas.Children.Add($bowRight) | Out-Null

        $knot = New-Object System.Windows.Shapes.Ellipse
        $knot.Width = 8
        $knot.Height = 8
        $knot.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($knot, $bx - 4) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($knot, $by - 4) | Out-Null
        $canvas.Children.Add($knot) | Out-Null
    }
}

##################################################
# Twinkle updates
##################################################
function Set-LightColor {
    param($lightObj,[System.Windows.Media.Color]$Color)

    $lightObj.Core.Fill = New-SolidBrush $Color
    $lightObj.Glow.Fill = New-RadialGlowBrush $Color
}

function Update-Twinkles {
    $script:frame++

    foreach ($s in $script:BgStars) {
        if (ShouldTwinkle 10) {
            $shape = $s.Shape
            $shape.Fill = New-SolidBrush ($bgStarPalette[(Get-Random -Maximum $bgStarPalette.Count)])
            $shape.Opacity = Clamp ($s.BaseOpacity + ((Get-Random -Minimum -30 -Maximum 31)/100.0)) 0.05 1.0
        }
    }

    foreach ($l in $script:LightObjs) {
        if (ShouldTwinkle 3) {
            $ci = Get-Random -Maximum $lightPalette.Count
            $l.ColorIndex = $ci
            Set-LightColor -lightObj $l -Color $lightPalette[$ci]
        }

        if (ShouldTwinkle 2) {
            $b = $l.BaseOpacity
            $l.Glow.Opacity = Clamp ($b + ((Get-Random -Minimum -20 -Maximum 21)/100.0)) 0.25 1.0
            $l.Core.Opacity = Clamp (0.8 + ((Get-Random -Minimum 0 -Maximum 21)/100.0)) 0.65 1.0
        }
    }

    foreach ($seg in $script:StarSegments) {
        if (ShouldTwinkle 2) {
            $seg.Shape.Opacity = Clamp ($seg.BaseOpacity + ((Get-Random -Minimum -25 -Maximum 26)/100.0)) 0.25 1.0
        }
        if (ShouldTwinkle 7) {
            $k = Get-Random -Maximum $starSegmentColors.Count
            $seg.Shape.Fill = New-SolidBrush $starSegmentColors[$k]
        }
    }
}

##################################################
# Build scene
##################################################
Draw-BackgroundStars -Count 200
Draw-TreeBranches
Draw-Lights -Count 400
Draw-TopStar
Draw-Presents

##################################################
# Smooth animation timer
##################################################
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({ Update-Twinkles })
$timer.Start()

$app = New-Object System.Windows.Application
[void]$app.Run($window)$window.WindowStartupLocation = "CenterScreen"

$sceneW = [double]$window.Width
$sceneH = [double]$window.Height

# Sky gradient background
$sky = New-Object System.Windows.Media.LinearGradientBrush
$sky.StartPoint = New-Object System.Windows.Point(0.5, 0.0)
$sky.EndPoint = New-Object System.Windows.Point(0.5, 1.0)
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(8,12,35)), 0.0)))
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(18,22,60)), 0.55)))
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::Black), 1.0)))
$window.Background = $sky

$canvas = New-Object System.Windows.Controls.Canvas
$canvas.Width = $sceneW
$canvas.Height = $sceneH
$window.Content = $canvas

##################################################
# Tree Parameters
##################################################
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

##################################################
# Storage
##################################################
$script:BgStars = @()
$script:BrightStars = @()
$script:Lights = @()
$script:SnowFlakes = @()
$script:ShootingStars = @()
$script:NextShootAt = Get-Random -Minimum 80 -Maximum 220
$script:frame = 0

##################################################
# Draw Background Stars
##################################################
function Draw-BackgroundStars {
    for ($i=0; $i -lt 200; $i++) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = (Get-Random -Minimum 1 -Maximum 3)
        $e.Height = $e.Width
        $e.Fill = [System.Windows.Media.Brushes]::White
        $base = (Get-Random -Minimum 5 -Maximum 60) / 100.0
        $e.Opacity = $base
        [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$sceneW)))
        [System.Windows.Controls.Canvas]::SetTop($e, (Get-Random -Minimum 0 -Maximum ([int]$sceneH)))
        $canvas.Children.Add($e) | Out-Null
        $script:BgStars += @{ Shape = $e; BaseOpacity = $base }
    }
    
    # Bright stars with glow
    for ($i=0; $i -lt 100; $i++) {
        $e = New-Object System.Windows.Shapes.Ellipse
        $sz = (Get-Random -Minimum 3 -Maximum 6)
        $e.Width = $sz
        $e.Height = $sz
        
        $g = New-Object System.Windows.Media.RadialGradientBrush
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White, 0.0)))
        $mid = [System.Windows.Media.Colors]::White
        $mid.A = 160
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid, 0.35)))
        $fade = [System.Windows.Media.Colors]::White
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade, 1.0)))
        
        $e.Fill = $g
        $base = (Get-Random -Minimum 55 -Maximum 95) / 100.0
        $e.Opacity = $base
        [System.Windows.Controls.Canvas]::SetLeft($e, (Get-Random -Minimum 0 -Maximum ([int]$sceneW)))
        [System.Windows.Controls.Canvas]::SetTop($e, (Get-Random -Minimum 0 -Maximum ([int]($sceneH * 0.75))))
        $canvas.Children.Add($e) | Out-Null
        $script:BrightStars += @{ Shape = $e; BaseOpacity = $base }
    }
}

##################################################
# Draw Tree Branches
##################################################
function Draw-TreeBranches {
    $stroke1 = [System.Windows.Media.Brushes]::ForestGreen
    $stroke2 = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(12,95,30))
    
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
            $ln.StrokeStartLineCap = "Round"
            $ln.StrokeEndLineCap = "Round"
            $ln.Opacity = 0.9
            $canvas.Children.Add($ln) | Out-Null
        }
    }
}

##################################################
# Draw Presents
##################################################
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
    
    for ($i=0; $i -lt 14; $i++) {
        $w = Get-Random -Minimum 60 -Maximum 140
        $h = Get-Random -Minimum 45 -Maximum 95
        $x = $treeCenterX + (Get-Random -Minimum -260 -Maximum 260)
        $y = $baseY - $h + (Get-Random -Minimum -10 -Maximum 12)
        $col = $palette[(Get-Random -Maximum $palette.Count)]
        
        # Shadow
        $shadow = New-Object System.Windows.Shapes.Rectangle
        $shadow.Width = $w + 10
        $shadow.Height = $h + 10
        $shadow.RadiusX = 10
        $shadow.RadiusY = 10
        $shadow.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(70,0,0,0))
        [System.Windows.Controls.Canvas]::SetLeft($shadow, ($x + 6))
        [System.Windows.Controls.Canvas]::SetTop($shadow, ($y + 6))
        $canvas.Children.Add($shadow) | Out-Null
        
        # Box with gradient
        $box = New-Object System.Windows.Shapes.Rectangle
        $box.Width = $w
        $box.Height = $h
        $box.RadiusX = 8
        $box.RadiusY = 8
        
        $grad = New-Object System.Windows.Media.LinearGradientBrush
        $grad.StartPoint = New-Object System.Windows.Point(0, 0)
        $grad.EndPoint = New-Object System.Windows.Point(1, 1)
        
        $dark = $col
        $dark.R = [byte]($dark.R * 0.7)
        $dark.G = [byte]($dark.G * 0.7)
        $dark.B = [byte]($dark.B * 0.7)
        
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($col, 0.0)))
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($col, 0.35)))
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($dark, 1.0)))
        
        $box.Fill = $grad
        [System.Windows.Controls.Canvas]::SetLeft($box, $x)
        [System.Windows.Controls.Canvas]::SetTop($box, $y)
        $canvas.Children.Add($box) | Out-Null
        
        # Highlight
        $shine = New-Object System.Windows.Shapes.Rectangle
        $shine.Width = [Math]::Max(10, $w * 0.22)
        $shine.Height = $h - 8
        $shine.RadiusX = 6
        $shine.RadiusY = 6
        $shine.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(45,255,255,255))
        [System.Windows.Controls.Canvas]::SetLeft($shine, ($x + 8))
        [System.Windows.Controls.Canvas]::SetTop($shine, ($y + 4))
        $canvas.Children.Add($shine) | Out-Null
        
        # Ribbon
        $rcol = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { [System.Windows.Media.Brushes]::Gold } else { [System.Windows.Media.Brushes]::White }
        $centerX = $x + ($w / 2.0)
        
        $ribV = New-Object System.Windows.Shapes.Rectangle
        $ribV.Width = 10
        $ribV.Height = $h
        $ribV.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribV, ($centerX - 5.0))
        [System.Windows.Controls.Canvas]::SetTop($ribV, $y)
        $canvas.Children.Add($ribV) | Out-Null
        
        $ribH = New-Object System.Windows.Shapes.Rectangle
        $ribH.Width = $w
        $ribH.Height = 10
        $ribH.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribH, $x)
        [System.Windows.Controls.Canvas]::SetTop($ribH, (($y + ($h / 2.0)) - 5.0))
        $canvas.Children.Add($ribH) | Out-Null
        
        # Bow
        $bowY = $y - 6.0
        
        $knot = New-Object System.Windows.Shapes.Ellipse
        $knot.Width = 8
        $knot.Height = 8
        $knot.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($knot, ($centerX - 4.0))
        [System.Windows.Controls.Canvas]::SetTop($knot, $bowY)
        $canvas.Children.Add($knot) | Out-Null
        
        $bowL = New-Object System.Windows.Shapes.Polygon
        $bowL.Fill = $rcol
        $pcl = New-Object System.Windows.Media.PointCollection
        $pcl.Add((New-Object System.Windows.Point($centerX, ($bowY + 4))))
        $pcl.Add((New-Object System.Windows.Point(($centerX - 18), ($bowY - 10))))
        $pcl.Add((New-Object System.Windows.Point(($centerX - 6), ($bowY + 2))))
        $bowL.Points = $pcl
        $canvas.Children.Add($bowL) | Out-Null
        
        $bowR = New-Object System.Windows.Shapes.Polygon
        $bowR.Fill = $rcol
        $pcr = New-Object System.Windows.Media.PointCollection
        $pcr.Add((New-Object System.Windows.Point($centerX, ($bowY + 4))))
        $pcr.Add((New-Object System.Windows.Point(($centerX + 18), ($bowY - 10))))
        $pcr.Add((New-Object System.Windows.Point(($centerX + 6), ($bowY + 2))))
        $bowR.Points = $pcr
        $canvas.Children.Add($bowR) | Out-Null
    }
}

##################################################
# Create Lights
##################################################
function Create-Lights {
    $lightColors = @(
        [System.Windows.Media.Colors]::Red,
        [System.Windows.Media.Colors]::Yellow,
        [System.Windows.Media.Colors]::DeepSkyBlue,
        [System.Windows.Media.Colors]::Lime,
        [System.Windows.Media.Colors]::Magenta,
        [System.Windows.Media.Colors]::Cyan,
        [System.Windows.Media.Colors]::Orange
    )
    
    for ($i=0; $i -lt 400; $i++) {
        $y = $treeTopY + (Rand01 * $treeHeight)
        $hw = Tree-HalfWidthAtY $y
        $x = $treeCenterX + (RandRange (-1.0 * $hw) $hw)
        
        # Glow
        $glow = New-Object System.Windows.Shapes.Ellipse
        $glow.Width = 18
        $glow.Height = 18
        
        $ci = Get-Random -Maximum $lightColors.Count
        $c = $lightColors[$ci]
        
        $g = New-Object System.Windows.Media.RadialGradientBrush
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c, 0.0)))
        $mid = $c
        $mid.A = 120
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid, 0.40)))
        $fade = $c
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade, 1.0)))
        
        $glow.Fill = $g
        $baseGO = 0.70 + (Rand01 / 6.0)
        $glow.Opacity = $baseGO
        
        [System.Windows.Controls.Canvas]::SetLeft($glow, ($x - 9))
        [System.Windows.Controls.Canvas]::SetTop($glow, ($y - 9))
        $canvas.Children.Add($glow) | Out-Null
        
        # Core
        $core = New-Object System.Windows.Shapes.Ellipse
        $core.Width = 7
        $core.Height = 7
        $core.Fill = New-Object System.Windows.Media.SolidColorBrush($c)
        $core.Opacity = 0.85
        
        [System.Windows.Controls.Canvas]::SetLeft($core, ($x - 3.5))
        [System.Windows.Controls.Canvas]::SetTop($core, ($y - 3.5))
        $canvas.Children.Add($core) | Out-Null
        
        $script:Lights += @{
            Glow = $glow
            Core = $core
            ColorIndex = $ci
            Colors = $lightColors
            BaseGO = $baseGO
        }
    }
}

##################################################
# Create Snow
##################################################
function Create-Snow {
    for ($i=0; $i -lt 120; $i++) {
        $size = Get-Random -Minimum 2 -Maximum 7
        
        $snow = New-Object System.Windows.Shapes.Ellipse
        $snow.Width = $size * 2
        $snow.Height = $size * 2
        
        $g = New-Object System.Windows.Media.RadialGradientBrush
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White, 0.0)))
        $mid = [System.Windows.Media.Colors]::White
        $mid.A = 110
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid, 0.35)))
        $fade = [System.Windows.Media.Colors]::White
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade, 1.0)))
        
        $snow.Fill = $g
        $baseO = 0.22 + (Rand01 / 6.0)
        $snow.Opacity = $baseO
        
        $x = Rand01 * $sceneW
        $y = Rand01 * $sceneH
        
        [System.Windows.Controls.Canvas]::SetLeft($snow, $x)
        [System.Windows.Controls.Canvas]::SetTop($snow, $y)
        $canvas.Children.Add($snow) | Out-Null
        
        $script:SnowFlakes += @{
            Shape = $snow
            X = $x
            Y = $y
            VX = ((Get-Random -Minimum -30 -Maximum 31) / 100.0)
            VY = (0.7 + (Rand01 / 1.3)) * (1.0 + ($size / 12.0))
            BaseO = $baseO
        }
    }
}

##################################################
# Create Shooting Star
##################################################
function New-ShootingStar {
    $line = New-Object System.Windows.Shapes.Line
    $line.X1 = (Get-Random -Minimum -200 -Maximum ([int]$sceneW)) * 1.0
    $line.Y1 = (Get-Random -Minimum 30 -Maximum 240) * 1.0
    $line.Stroke = [System.Windows.Media.Brushes]::White
    $line.StrokeThickness = 2
    $line.StrokeStartLineCap = "Round"
    $line.StrokeEndLineCap = "Round"
    $line.Opacity = 0.85
    
    $len = 55.0 + (Get-Random -Minimum 0 -Maximum 30)
    $line.X2 = $line.X1 - $len
    $line.Y2 = $line.Y1 - ($len * 0.25)
    
    $canvas.Children.Add($line) | Out-Null
    
    @{
        Shape = $line
        VX = 14.0 + ((Get-Random -Minimum 0 -Maximum 90) / 10.0)
        VY = 3.0 + ((Get-Random -Minimum 0 -Maximum 60) / 10.0)
        Life = 0
        MaxLife = Get-Random -Minimum 35 -Maximum 80
        Len = $len
    }
}

##################################################
# Animation Update
##################################################
function Update-Scene {
    $script:frame++
    
    # Update lights
    if (($script:frame % 2) -eq 0) {
        foreach ($l in $script:Lights) {
            if (ShouldTwinkle 3) {
                $l.ColorIndex = Get-Random -Maximum $l.Colors.Count
                $c = $l.Colors[$l.ColorIndex]
                $l.Core.Fill = New-Object System.Windows.Media.SolidColorBrush($c)
                
                $g = New-Object System.Windows.Media.RadialGradientBrush
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c, 0.0)))
                $mid = $c
                $mid.A = 120
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid, 0.40)))
                $fade = $c
                $fade.A = 0
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade, 1.0)))
                $l.Glow.Fill = $g
            }
            
            $l.Glow.Opacity = Clamp ($l.BaseGO + ((Get-Random -Minimum -10 -Maximum 11)/100.0)) 0.30 1.00
            $l.Core.Opacity = Clamp (0.78 + ((Get-Random -Minimum -6 -Maximum 7)/100.0)) 0.65 1.00
        }
    }
    
    # Update snow
    foreach ($s in $script:SnowFlakes) {
        $s.X = $s.X + $s.VX
        $s.Y = $s.Y + $s.VY
        
        if ($s.X -gt ($sceneW + 20)) { $s.X = -20 }
        if ($s.X -lt -20) { $s.X = $sceneW + 20 }
        if ($s.Y -gt ($sceneH + 30)) { 
            $s.Y = -30
            $s.X = Rand01 * $sceneW
        }
        
        [System.Windows.Controls.Canvas]::SetLeft($s.Shape, $s.X)
        [System.Windows.Controls.Canvas]::SetTop($s.Shape, $s.Y)
        
        if (ShouldTwinkle 35) {
            $s.Shape.Opacity = Clamp ($s.BaseO + ((Get-Random -Minimum -10 -Maximum 11)/100.0)) 0.12 0.60
        }
    }
    
    # Update shooting stars
    $script:NextShootAt--
    if ($script:NextShootAt -le 0) {
        $script:NextShootAt = Get-Random -Minimum 80 -Maximum 220
        $n = Get-Random -Minimum 1 -Maximum 3
        for ($i=0; $i -lt $n; $i++) {
            $script:ShootingStars += (New-ShootingStar)
        }
    }
    
    $alive = @()
    foreach ($st in $script:ShootingStars) {
        $st.Life++
        $fade = Clamp (1.0 - ($st.Life / [double]$st.MaxLife)) 0 1
        $st.Shape.Opacity = 0.85 * $fade
        
        $st.Shape.X1 = $st.Shape.X1 + $st.VX
        $st.Shape.Y1 = $st.Shape.Y1 + $st.VY
        $st.Shape.X2 = $st.Shape.X1 - $st.Len
        $st.Shape.Y2 = $st.Shape.Y1 - ($st.Len * 0.25)
        
        if ($st.Life -lt $st.MaxLife -and $st.Shape.X1 -lt ($sceneW + 250) -and $st.Shape.Y1 -lt ($sceneH + 250)) {
            $alive += $st
        } else {
            $canvas.Children.Remove($st.Shape)
        }
    }
    $script:ShootingStars = $alive
    
    # Update background stars
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

##################################################
# Build Scene
##################################################
Draw-BackgroundStars
Draw-TreeBranches
Draw-Presents
Create-Lights
Create-Snow

##################################################
# Animation Timer
##################################################
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({ Update-Scene })
$timer.Start()

##################################################
# Run Application
##################################################
$app = New-Object System.Windows.Application
[void]$app.Run($window)

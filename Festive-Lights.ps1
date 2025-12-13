#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

##################################################
# Window and canvas
##################################################
$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Width = 900
$window.Height = 700
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
        [byte]$MidAlpha = 120
    )
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.Center = New-Object System.Windows.Point(0.5,0.5)
    $g.GradientOrigin = New-Object System.Windows.Point(0.5,0.5)
    $g.RadiusX = 0.5
    $g.RadiusY = 0.5

    $c1 = $Color
    $c2 = $Color
    $c3 = $Color
    $c2.A = $MidAlpha
    $c3.A = 0

    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c1,0.0))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c2,0.35))) | Out-Null
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c3,1.0))) | Out-Null
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

$treeCenterX = $sceneW / 2.0
$treeTopY = 70.0
$treeHeight = 440.0
$treeBaseY = $treeTopY + $treeHeight
$treeMaxHalfWidth = 240.0

$trunkHeight = 75.0
$trunkWidth = 50.0

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
$script:LightObjs = @()         # @{Glow; Core; BaseOpacity; ColorIndex; X; Y}
$script:BgStars = @()           # @{Shape; BaseOpacity}
$script:BrightStars = @()       # @{Shape; BaseOpacity}
$script:StarSegments = @()      # @{Shape; BaseOpacity}
$script:Snow = @()              # @{Glow; Core; X; Y; VX; VY; Size; BaseOpacity}
$script:Village = @()           # @{Shape; BaseOpacity; WarmIndex}
$script:ShootingStars = @()     # @{Glow; Core; Active; X; Y; VX; VY; Life; MaxLife}
$script:nextShootAt = 0
$script:frame = 0

$script:keyBoost = 0.0
$script:wind = 0.0
$script:windTicks = 0

# Elastic sway state
$script:branchSwayPos = 0.0
$script:branchSwayVel = 0.0
$script:branchSwayTarget = 0.0

# Snow drift state
$script:snowDriftPos = 0.0
$script:snowDriftVel = 0.0
$script:snowDriftTarget = 0.0

# One shared transform for all branches
$script:branchTranslate = New-Object System.Windows.Media.TranslateTransform(0,0)
$script:branchRotate = New-Object System.Windows.Media.RotateTransform(0)
$script:branchXform = New-Object System.Windows.Media.TransformGroup
$script:branchXform.Children.Add($script:branchRotate) | Out-Null
$script:branchXform.Children.Add($script:branchTranslate) | Out-Null

##################################################
# Sky gradient background that shifts slowly
##################################################
$script:skyBrush = New-Object System.Windows.Media.LinearGradientBrush
$script:skyBrush.StartPoint = New-Object System.Windows.Point(0.5,0.0)
$script:skyBrush.EndPoint = New-Object System.Windows.Point(0.5,1.0)
$script:skyTopStop = New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::MidnightBlue),0.0)
$script:skyMidStop = New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::DarkSlateBlue),0.55)
$script:skyHznStop = New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::Black),1.0)
$script:skyBrush.GradientStops.Add($script:skyTopStop) | Out-Null
$script:skyBrush.GradientStops.Add($script:skyMidStop) | Out-Null
$script:skyBrush.GradientStops.Add($script:skyHznStop) | Out-Null
$window.Background = $script:skyBrush

function Update-Sky {
    $cycle = 2400.0
    $t = [Math]::Sin(($script:frame / $cycle) * 2.0 * [Math]::PI) * 0.5 + 0.5

    $nightTop = [System.Windows.Media.Color]::FromRgb(8,12,35)
    $dawnTop  = [System.Windows.Media.Color]::FromRgb(30,35,85)

    $nightMid = [System.Windows.Media.Color]::FromRgb(6,8,20)
    $dawnMid  = [System.Windows.Media.Color]::FromRgb(22,22,55)

    $top = New-Object System.Windows.Media.Color
    $top.A = 255
    $top.R = [byte](($nightTop.R * (1-$t)) + ($dawnTop.R * $t))
    $top.G = [byte](($nightTop.G * (1-$t)) + ($dawnTop.G * $t))
    $top.B = [byte](($nightTop.B * (1-$t)) + ($dawnTop.B * $t))

    $mid = New-Object System.Windows.Media.Color
    $mid.A = 255
    $mid.R = [byte](($nightMid.R * (1-$t)) + ($dawnMid.R * $t))
    $mid.G = [byte](($nightMid.G * (1-$t)) + ($dawnMid.G * $t))
    $mid.B = [byte](($nightMid.B * (1-$t)) + ($dawnMid.B * $t))

    $script:skyTopStop.Color = $top
    $script:skyMidStop.Color = $mid
    $script:skyHznStop.Color = [System.Windows.Media.Colors]::Black
}

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
# Background stars and brighter stars
##################################################
function Draw-BackgroundStars {
    param([int]$Count = 200, [int]$BrightCount = 100)

    for ($i=0; $i -lt $Count; $i++) {
        $x = Get-Random -Minimum 0 -Maximum ([int]$sceneW)
        $y = Get-Random -Minimum 0 -Maximum ([int]$sceneH)
        if (Is-InTreeCone $x $y) { continue }

        $e = New-Object System.Windows.Shapes.Ellipse
        $e.Width = (Get-Random -Minimum 1 -Maximum 3)
        $e.Height = $e.Width
        $e.Fill = New-SolidBrush ($bgStarPalette[(Get-Random -Maximum $bgStarPalette.Count)])
        $base = (Get-Random -Minimum 10 -Maximum 70) / 100.0
        $e.Opacity = $base

        [System.Windows.Controls.Canvas]::SetLeft($e, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e, $y) | Out-Null
        $canvas.Children.Add($e) | Out-Null

        $script:BgStars += @{ Shape = $e; BaseOpacity = $base }
    }

    for ($i=0; $i -lt $BrightCount; $i++) {
        $x = Get-Random -Minimum 0 -Maximum ([int]$sceneW)
        $y = Get-Random -Minimum 0 -Maximum ([int]($sceneH * 0.75))
        if (Is-InTreeCone $x $y) { continue }

        $e = New-Object System.Windows.Shapes.Ellipse
        $sz = (Get-Random -Minimum 2 -Maximum 5)
        $e.Width = $sz
        $e.Height = $sz
        $c = [System.Windows.Media.Colors]::White
        $e.Fill = New-RadialGlowBrush -Color $c -MidAlpha 160
        $base = (Get-Random -Minimum 55 -Maximum 95) / 100.0
        $e.Opacity = $base

        [System.Windows.Controls.Canvas]::SetLeft($e, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e, $y) | Out-Null
        $canvas.Children.Add($e) | Out-Null

        $script:BrightStars += @{ Shape = $e; BaseOpacity = $base }
    }
}

##################################################
# Tree branches, no solid fill
##################################################
function Draw-TreeBranches {
    $layers = 22
    $layerStep = $treeHeight / $layers

    for ($li=0; $li -lt $layers; $li++) {
        $y = $treeTopY + ($li * $layerStep)
        $hw = Tree-HalfWidthAtY ($y + ($layerStep * 0.8))

        $primaryCount = 10
        for ($p=0; $p -lt $primaryCount; $p++) {
            $yy = $y + (Get-Random -Minimum -6 -Maximum 7) + (Get-Random -Minimum 0 -Maximum ([int]($layerStep * 0.9)))
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

            $pl.RenderTransform = $script:branchXform
            $pl.RenderTransformOrigin = New-Object System.Windows.Point(0.5,1.0)

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

                $ln.RenderTransform = $script:branchXform
                $ln.RenderTransformOrigin = New-Object System.Windows.Point(0.5,1.0)

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
        X = $x
        Y = $y
    }
}

function Set-LightColor {
    param($lightObj,[System.Windows.Media.Color]$Color)
    $lightObj.Core.Fill = New-SolidBrush $Color
    $lightObj.Glow.Fill = New-RadialGlowBrush $Color
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
        $o = New-LightObject -x $x -y $y -color $lightPalette[$ci]
        $o.ColorIndex = $ci
        $script:LightObjs += $o
    }
}

##################################################
# Multicolour 5 point star
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
        $points += ,(New-Object System.Windows.Point($cx + ($r * [Math]::Cos($ang)), $cy + ($r * [Math]::Sin($ang))))
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

        $poly.Fill = New-SolidBrush ($starSegmentColors[$k])
        $poly.Stroke = New-SolidBrush ([System.Windows.Media.Colors]::White)
        $poly.StrokeThickness = 1.0
        $poly.Opacity = 0.95

        $canvas.Children.Add($poly) | Out-Null
        $script:StarSegments += @{ Shape = $poly; BaseOpacity = 0.85 + ((Get-Random -Minimum 0 -Maximum 10)/100.0) }
    }

    $gl = New-Object System.Windows.Shapes.Ellipse
    $gl.Width = 80
    $gl.Height = 80
    $gl.Fill = New-RadialGlowBrush ([System.Windows.Media.Colors]::Gold) 140
    $gl.Opacity = 0.5
    [System.Windows.Controls.Canvas]::SetLeft($gl, $cx - 40) | Out-Null
    [System.Windows.Controls.Canvas]::SetTop($gl, $cy - 40) | Out-Null
    $canvas.Children.Insert(0,$gl) | Out-Null
}

##################################################
# Presents
##################################################
function Draw-Presents {
    $baseY = [double]($treeBaseY + $trunkHeight - 5)
    $startX = [double]($treeCenterX - 210)

    $presentSpecs = @(
        @{ Fill = [System.Windows.Media.Colors]::Red;     X = ($startX + 0);   W = 90; H = 65 },
        @{ Fill = [System.Windows.Media.Colors]::Blue;    X = ($startX + 105); W = 85; H = 58 },
        @{ Fill = [System.Windows.Media.Colors]::Green;   X = ($startX + 205); W = 95; H = 70 },
        @{ Fill = [System.Windows.Media.Colors]::Magenta; X = ($startX + 320); W = 80; H = 60 }
    )

    foreach ($p in $presentSpecs) {
        $px = [double]$p["X"]
        $pw = [double]$p["W"]
        $ph = [double]$p["H"]
        $pf = $p["Fill"]

        $box = New-Object System.Windows.Shapes.Rectangle
        $box.Width = $pw
        $box.Height = $ph
        $box.RadiusX = 6
        $box.RadiusY = 6
        $box.Fill = New-SolidBrush $pf
        $box.Stroke = New-SolidBrush ([System.Windows.Media.Colors]::Black)
        $box.StrokeThickness = 1.0
        [System.Windows.Controls.Canvas]::SetLeft($box, $px) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($box, ($baseY - $ph)) | Out-Null
        $canvas.Children.Add($box) | Out-Null

        $rcol = [System.Windows.Media.Colors]::Gold
        if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $rcol = [System.Windows.Media.Colors]::White }

        $ribV = New-Object System.Windows.Shapes.Rectangle
        $ribV.Width = 10
        $ribV.Height = $ph
        $ribV.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribV, ($px + ($pw / 2.0) - 5.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribV, ($baseY - $ph)) | Out-Null
        $canvas.Children.Add($ribV) | Out-Null

        $ribH = New-Object System.Windows.Shapes.Rectangle
        $ribH.Width = $pw
        $ribH.Height = 10
        $ribH.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribH, $px) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribH, ($baseY - ($ph / 2.0) - 5.0)) | Out-Null
        $canvas.Children.Add($ribH) | Out-Null

        $bx = [double]($px + ($pw / 2.0))
        $by = [double](($baseY - $ph) - 4.0)

        $bowLeft = New-Object System.Windows.Shapes.Polygon
        $bowLeft.Fill = New-SolidBrush $rcol
        $bowLeftPts = New-Object System.Windows.Media.PointCollection
        $bowLeftPts.Add((New-Object System.Windows.Point($bx, $by))) | Out-Null
        $bowLeftPts.Add((New-Object System.Windows.Point(($bx - 18.0), ($by - 12.0)))) | Out-Null
        $bowLeftPts.Add((New-Object System.Windows.Point(($bx - 6.0), ($by - 2.0)))) | Out-Null
        $bowLeft.Points = $bowLeftPts
        $canvas.Children.Add($bowLeft) | Out-Null

        $bowRight = New-Object System.Windows.Shapes.Polygon
        $bowRight.Fill = New-SolidBrush $rcol
        $bowRightPts = New-Object System.Windows.Media.PointCollection
        $bowRightPts.Add((New-Object System.Windows.Point($bx, $by))) | Out-Null
        $bowRightPts.Add((New-Object System.Windows.Point(($bx + 18.0), ($by - 12.0)))) | Out-Null
        $bowRightPts.Add((New-Object System.Windows.Point(($bx + 6.0), ($by - 2.0)))) | Out-Null
        $bowRight.Points = $bowRightPts
        $canvas.Children.Add($bowRight) | Out-Null

        $knot = New-Object System.Windows.Shapes.Ellipse
        $knot.Width = 8
        $knot.Height = 8
        $knot.Fill = New-SolidBrush $rcol
        [System.Windows.Controls.Canvas]::SetLeft($knot, ($bx - 4.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($knot, ($by - 4.0)) | Out-Null
        $canvas.Children.Add($knot) | Out-Null
    }
}

##################################################
# Distant village lights
##################################################
function Draw-Village {
    $script:Village = @()
    $hznY = [double]($treeBaseY + $trunkHeight + 10)
    $hznY = Clamp $hznY ($sceneH * 0.72) ($sceneH - 40)

    $warm = @(
        [System.Windows.Media.Color]::FromRgb(255,210,120),
        [System.Windows.Media.Color]::FromRgb(255,180,90),
        [System.Windows.Media.Color]::FromRgb(255,235,170)
    )

    $count = 45
    for ($i=0; $i -lt $count; $i++) {
        $x = Get-Random -Minimum 10 -Maximum ([int]($sceneW - 10))
        $y = $hznY + (Get-Random -Minimum -8 -Maximum 12)

        $e = New-Object System.Windows.Shapes.Ellipse
        $sz = (Get-Random -Minimum 2 -Maximum 5)
        $e.Width = $sz
        $e.Height = $sz

        $ci = Get-Random -Maximum $warm.Count
        $e.Fill = New-RadialGlowBrush -Color $warm[$ci] -MidAlpha 150
        $base = (Get-Random -Minimum 25 -Maximum 65) / 100.0
        $e.Opacity = $base

        [System.Windows.Controls.Canvas]::SetLeft($e, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e, $y) | Out-Null
        $canvas.Children.Add($e) | Out-Null

        $script:Village += @{ Shape = $e; BaseOpacity = $base; WarmIndex = $ci }
    }
}

##################################################
# Snow with glow and drift
##################################################
function Draw-Snow {
    param([int]$Count = 160)

    $script:Snow = @()
    for ($i=0; $i -lt $Count; $i++) {
        $x = (Get-Random -Minimum 0 -Maximum ([int]$sceneW)) * 1.0
        $y = (Get-Random -Minimum 0 -Maximum ([int]$sceneH)) * 1.0

        $size = (Get-Random -Minimum 2 -Maximum 7) * 1.0
        $vy = (0.7 + ((Get-Random -Minimum 0 -Maximum 190) / 100.0)) * (1.0 + ($size / 10.0))
        $vx = ((Get-Random -Minimum -40 -Maximum 41) / 100.0)

        $c = [System.Windows.Media.Color]::FromRgb(255,255,255)
        $glow = New-Object System.Windows.Shapes.Ellipse
        $glow.Width = $size * 3.0
        $glow.Height = $size * 3.0
        $glow.Fill = New-RadialGlowBrush -Color $c -MidAlpha 120
        $glow.Opacity = 0.35

        $core = New-Object System.Windows.Shapes.Ellipse
        $core.Width = $size
        $core.Height = $size
        $core.Fill = New-SolidBrush $c
        $core.Opacity = 0.65

        $canvas.Children.Add($glow) | Out-Null
        $canvas.Children.Add($core) | Out-Null

        [System.Windows.Controls.Canvas]::SetLeft($glow, $x - ($glow.Width/2.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($glow, $y - ($glow.Height/2.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetLeft($core, $x - ($core.Width/2.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($core, $y - ($core.Height/2.0)) | Out-Null

        $script:Snow += @{
            Glow = $glow
            Core = $core
            X = $x
            Y = $y
            VX = $vx
            VY = $vy
            Size = $size
            BaseOpacity = 0.35 + ((Get-Random -Minimum 0 -Maximum 30)/100.0)
        }
    }
}

##################################################
# Shooting stars
##################################################
function New-ShootingStar {
    $x = (Get-Random -Minimum -200 -Maximum ([int]$sceneW)) * 1.0
    $y = (Get-Random -Minimum 20 -Maximum 220) * 1.0

    $vx = (10.0 + ((Get-Random -Minimum 0 -Maximum 80)/10.0))
    $vy = (2.0 + ((Get-Random -Minimum 0 -Maximum 50)/10.0))

    $life = 0
    $maxLife = Get-Random -Minimum 35 -Maximum 75

    $core = New-Object System.Windows.Shapes.Line
    $core.StrokeThickness = 2.0
    $core.StrokeStartLineCap = "Round"
    $core.StrokeEndLineCap = "Round"
    $core.Opacity = 0.9
    $core.Stroke = New-SolidBrush ([System.Windows.Media.Colors]::White)

    $glow = New-Object System.Windows.Shapes.Line
    $glow.StrokeThickness = 6.0
    $glow.StrokeStartLineCap = "Round"
    $glow.StrokeEndLineCap = "Round"
    $glow.Opacity = 0.35
    $glow.Stroke = New-RadialGlowBrush ([System.Windows.Media.Colors]::White) 140

    $canvas.Children.Add($glow) | Out-Null
    $canvas.Children.Add($core) | Out-Null

    @{
        Glow = $glow
        Core = $core
        Active = $true
        X = $x
        Y = $y
        VX = $vx
        VY = $vy
        Life = $life
        MaxLife = $maxLife
    }
}

function Launch-ShootingStar {
    $script:ShootingStars += (New-ShootingStar)
}

##################################################
# Twinkle and motion updates
##################################################
function Apply-LightPositions {
    param([double]$swayX)

    foreach ($l in $script:LightObjs) {
        $x = [double]$l.X + $swayX
        $y = [double]$l.Y

        [System.Windows.Controls.Canvas]::SetLeft($l.Glow, $x - 9.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($l.Glow, $y - 9.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetLeft($l.Core, $x - 3.5) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($l.Core, $y - 3.5) | Out-Null
    }
}

function Update-TwinklesAndMotion {
    $script:frame++

    Update-Sky

    if ($script:keyBoost -gt 0) { $script:keyBoost = Clamp ($script:keyBoost - 0.05) 0 1 }

    if ($script:windTicks -gt 0) {
        $script:windTicks--
        $script:wind = $script:wind * 0.92
    } else {
        $script:wind = $script:wind * 0.90
    }

    # Springy elastic branch sway
    $k = 0.18
    $d = 0.82
    $force = ($script:branchSwayTarget - $script:branchSwayPos) * $k
    $script:branchSwayVel = ($script:branchSwayVel + $force) * $d
    $script:branchSwayPos = $script:branchSwayPos + $script:branchSwayVel

    # Ease snow drift
    $k2 = 0.10
    $d2 = 0.88
    $force2 = ($script:snowDriftTarget - $script:snowDriftPos) * $k2
    $script:snowDriftVel = ($script:snowDriftVel + $force2) * $d2
    $script:snowDriftPos = $script:snowDriftPos + $script:snowDriftVel

    # Apply branch transform
    $script:branchTranslate.X = $script:branchSwayPos
    $script:branchRotate.Angle = ($script:branchSwayPos * 0.25)
    $script:branchRotate.CenterX = $treeCenterX
    $script:branchRotate.CenterY = ($treeBaseY + 30.0)

    $swayX = [Math]::Sin($script:frame / 6.0) * (6.0 * $script:wind)
    Apply-LightPositions -swayX $swayX

    foreach ($s in $script:BgStars) {
        if (ShouldTwinkle 10) {
            $s.Shape.Fill = New-SolidBrush ($bgStarPalette[(Get-Random -Maximum $bgStarPalette.Count)])
            $s.Shape.Opacity = Clamp ($s.BaseOpacity + ((Get-Random -Minimum -30 -Maximum 31)/100.0)) 0.05 1.0
        }
    }

    foreach ($s in $script:BrightStars) {
        if (ShouldTwinkle 8) {
            $s.Shape.Opacity = Clamp ($s.BaseOpacity + ((Get-Random -Minimum -20 -Maximum 21)/100.0)) 0.25 1.0
        }
    }

    foreach ($v in $script:Village) {
        if (ShouldTwinkle 4) {
            $v.Shape.Opacity = Clamp ($v.BaseOpacity + ((Get-Random -Minimum -15 -Maximum 16)/100.0)) 0.1 0.9
        }
    }

    foreach ($l in $script:LightObjs) {
        if (ShouldTwinkle 3) {
            $ci = Get-Random -Maximum $lightPalette.Count
            $l.ColorIndex = $ci
            Set-LightColor -lightObj $l -Color $lightPalette[$ci]
        }

        $boost = 0.18 * $script:keyBoost
        $baseGlow = $l.BaseOpacity
        $baseCore = 0.78

        $l.Glow.Opacity = Clamp (
            $baseGlow + $boost + ((Get-Random -Minimum -10 -Maximum 11) / 100.0)
        ) 0.25 1.0

        $l.Core.Opacity = Clamp (
            $baseCore + $boost + ((Get-Random -Minimum -6 -Maximum 7) / 100.0)
        ) 0.65 1.0
    }

    foreach ($seg in $script:StarSegments) {
        if (ShouldTwinkle 2) {
            $seg.Shape.Opacity = Clamp ($seg.BaseOpacity + ((Get-Random -Minimum -25 -Maximum 26)/100.0)) 0.25 1.0
        }
        if (ShouldTwinkle 7) {
            $kStar = Get-Random -Maximum $starSegmentColors.Count
            $seg.Shape.Fill = New-SolidBrush $starSegmentColors[$kStar]
        }
    }

    foreach ($f in $script:Snow) {
        $f.X = $f.X + $f.VX + $script:snowDriftPos + (0.55 * $script:wind) + (0.06 * $script:branchSwayPos)
        $f.Y = $f.Y + $f.VY

        if ($f.X -gt ($sceneW + 20)) { $f.X = -20 }
        if ($f.X -lt -20) { $f.X = $sceneW + 20 }
        if ($f.Y -gt ($sceneH + 30)) {
            $f.Y = -30
            $f.X = (Get-Random -Minimum 0 -Maximum ([int]$sceneW)) * 1.0
        }

        $gx = $f.X - ($f.Glow.Width/2.0)
        $gy = $f.Y - ($f.Glow.Height/2.0)
        $cx = $f.X - ($f.Core.Width/2.0)
        $cy = $f.Y - ($f.Core.Height/2.0)

        [System.Windows.Controls.Canvas]::SetLeft($f.Glow, $gx) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($f.Glow, $gy) | Out-Null
        [System.Windows.Controls.Canvas]::SetLeft($f.Core, $cx) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($f.Core, $cy) | Out-Null

        if (ShouldTwinkle 35) {
            $f.Glow.Opacity = Clamp ($f.BaseOpacity + ((Get-Random -Minimum -10 -Maximum 11)/100.0)) 0.15 0.65
            $f.Core.Opacity = Clamp (0.55 + ((Get-Random -Minimum -15 -Maximum 16)/100.0)) 0.25 0.85
        }
    }

    if ($script:nextShootAt -le 0) {
        $script:nextShootAt = Get-Random -Minimum 80 -Maximum 220
    } else {
        $script:nextShootAt--
        if ($script:nextShootAt -eq 0) {
            $count = Get-Random -Minimum 1 -Maximum 3
            for ($i=0; $i -lt $count; $i++) { Launch-ShootingStar }
        }
    }

    $alive = @()
    foreach ($st in $script:ShootingStars) {
        if (-not $st.Active) { continue }

        $st.Life++
        $st.X = $st.X + $st.VX
        $st.Y = $st.Y + $st.VY

        $tail = 45.0
        $x2 = $st.X
        $y2 = $st.Y
        $x1 = $st.X - $tail
        $y1 = $st.Y - ($tail * 0.25)

        $fade = 1.0 - ($st.Life / [double]$st.MaxLife)
        $fade = Clamp $fade 0 1

        $st.Core.X1 = $x1; $st.Core.Y1 = $y1
        $st.Core.X2 = $x2; $st.Core.Y2 = $y2
        $st.Glow.X1 = $x1; $st.Glow.Y1 = $y1
        $st.Glow.X2 = $x2; $st.Glow.Y2 = $y2
        $st.Core.Opacity = 0.85 * $fade
        $st.Glow.Opacity = 0.35 * $fade

        if ($st.Life -ge $st.MaxLife -or $st.X -gt ($sceneW + 200) -or $st.Y -gt ($sceneH + 200)) {
            $st.Active = $false
            $canvas.Children.Remove($st.Core) | Out-Null
            $canvas.Children.Remove($st.Glow) | Out-Null
        } else {
            $alive += $st
        }
    }
    $script:ShootingStars = $alive
}

##################################################
# Interactive input
##################################################
$window.Add_KeyDown({
    $script:keyBoost = 1.0
    $script:wind = 1.0
    $script:windTicks = Get-Random -Minimum 25 -Maximum 60
    $script:branchSwayTarget = ((Get-Random -Minimum -100 -Maximum 101) / 100.0) * 10.0
    $script:snowDriftTarget = ((Get-Random -Minimum -100 -Maximum 101) / 100.0) * 0.9
})

##################################################
# Build scene
##################################################
Draw-BackgroundStars -Count 200 -BrightCount 100
Draw-Village
Draw-TreeBranches
Draw-Lights -Count 400
Draw-TopStar
Draw-Presents
Draw-Snow -Count 170

##################################################
# Smooth animation timer
##################################################
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({ Update-TwinklesAndMotion })
$timer.Start()

##################################################
# Run app, safe for reruns
##################################################
$app = [System.Windows.Application]::Current
if (-not $app) {
    $app = New-Object System.Windows.Application
    [void]$app.Run($window)
} else {
    [void]$window.ShowDialog()
}

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
        $knot.Fill = New-Object System.Windows.Media.SolidColorBrush($rcol)
        [System.Windows.Controls.Canvas]::SetLeft($knot, ($bx - 4.0)) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($knot, ($by - 4.0)) | Out-Null
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

# Show the window and start the application's message loop
$app = [System.Windows.Application]::Current
if (-not $app) {
    $app = New-Object System.Windows.Application
}

# If the app is already running (ISE etc) do not call Run again
if ($app.Dispatcher -and $app.Dispatcher.HasShutdownStarted) {
    $app = New-Object System.Windows.Application
}

if ($app -and ($app.Windows.Count -eq 0)) {
    [void]$app.Run($window)
} else {
    [void]$window.Show()
}

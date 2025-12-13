#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

##################################################
# Helper Functions
##################################################
function Clamp {
    param([double]$v,[double]$min,[double]$max)
    if ($v -lt $min) { return $min }
    if ($v -gt $max) { return $max }
    $v
}

function ShouldTwinkle {
    param([int]$Chance = 7)
    (Get-Random -Minimum 1 -Maximum ($Chance + 1)) -eq 1
}

function Rand01 {
    (Get-Random -Minimum 0 -Maximum 1000000) / 1000000.0
}

function RandRange {
    param([double]$min,[double]$max)
    $min + ((Rand01) * ($max - $min))
}

##################################################
# Window Setup
##################################################
$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Width = 900
$window.Height = 700
$window.WindowStartupLocation = "CenterScreen"

$sceneW = [double]$window.Width
$sceneH = [double]$window.Height

# Sky gradient background
$sky = New-Object System.Windows.Media.LinearGradientBrush
$sky.StartPoint = New-Object System.Windows.Point(0.5,0.0)
$sky.EndPoint = New-Object System.Windows.Point(0.5,1.0)
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(8,12,35)),0.0))) | Out-Null
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Color]::FromRgb(18,22,60)),0.55))) | Out-Null
$sky.GradientStops.Add((New-Object System.Windows.Media.GradientStop(([System.Windows.Media.Colors]::Black),1.0))) | Out-Null
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
        [System.Windows.Controls.Canvas]::SetLeft($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneW))) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneH))) | Out-Null
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
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White,0.0))) | Out-Null
        $mid = [System.Windows.Media.Colors]::White
        $mid.A = 160
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.35))) | Out-Null
        $fade = [System.Windows.Media.Colors]::White
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
        
        $e.Fill = $g
        $base = (Get-Random -Minimum 55 -Maximum 95) / 100.0
        $e.Opacity = $base
        [System.Windows.Controls.Canvas]::SetLeft($e,(Get-Random -Minimum 0 -Maximum ([int]$sceneW))) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($e,(Get-Random -Minimum 0 -Maximum ([int]($sceneH * 0.75)))) | Out-Null
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
        [System.Windows.Controls.Canvas]::SetLeft($shadow, $x + 6) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($shadow, $y + 6) | Out-Null
        $canvas.Children.Add($shadow) | Out-Null
        
        # Box with gradient
        $box = New-Object System.Windows.Shapes.Rectangle
        $box.Width = $w
        $box.Height = $h
        $box.RadiusX = 8
        $box.RadiusY = 8
        
        $grad = New-Object System.Windows.Media.LinearGradientBrush
        $grad.StartPoint = New-Object System.Windows.Point(0,0)
        $grad.EndPoint = New-Object System.Windows.Point(1,1)
        
        $dark = $col
        $dark.R = [byte]($dark.R * 0.7)
        $dark.G = [byte]($dark.G * 0.7)
        $dark.B = [byte]($dark.B * 0.7)
        
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($col,0.0))) | Out-Null
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($col,0.35))) | Out-Null
        $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop($dark,1.0))) | Out-Null
        
        $box.Fill = $grad
        [System.Windows.Controls.Canvas]::SetLeft($box, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($box, $y) | Out-Null
        $canvas.Children.Add($box) | Out-Null
        
        # Highlight
        $shine = New-Object System.Windows.Shapes.Rectangle
        $shine.Width = [Math]::Max(10, $w * 0.22)
        $shine.Height = $h - 8
        $shine.RadiusX = 6
        $shine.RadiusY = 6
        $shine.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(45,255,255,255))
        [System.Windows.Controls.Canvas]::SetLeft($shine, $x + 8) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($shine, $y + 4) | Out-Null
        $canvas.Children.Add($shine) | Out-Null
        
        # Ribbon
        $rcol = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { [System.Windows.Media.Brushes]::Gold } else { [System.Windows.Media.Brushes]::White }
        $centerX = $x + ($w / 2.0)
        
        $ribV = New-Object System.Windows.Shapes.Rectangle
        $ribV.Width = 10
        $ribV.Height = $h
        $ribV.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribV, $centerX - 5.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribV, $y) | Out-Null
        $canvas.Children.Add($ribV) | Out-Null
        
        $ribH = New-Object System.Windows.Shapes.Rectangle
        $ribH.Width = $w
        $ribH.Height = 10
        $ribH.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($ribH, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($ribH, ($y + ($h / 2.0) - 5.0)) | Out-Null
        $canvas.Children.Add($ribH) | Out-Null
        
        # Bow
        $bowY = $y - 6.0
        
        $knot = New-Object System.Windows.Shapes.Ellipse
        $knot.Width = 8
        $knot.Height = 8
        $knot.Fill = $rcol
        [System.Windows.Controls.Canvas]::SetLeft($knot, $centerX - 4.0) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($knot, $bowY) | Out-Null
        $canvas.Children.Add($knot) | Out-Null
        
        $bowL = New-Object System.Windows.Shapes.Polygon
        $bowL.Fill = $rcol
        $pcl = New-Object System.Windows.Media.PointCollection
        $pcl.Add((New-Object System.Windows.Point($centerX, $bowY + 4))) | Out-Null
        $pcl.Add((New-Object System.Windows.Point($centerX - 18, $bowY - 10))) | Out-Null
        $pcl.Add((New-Object System.Windows.Point($centerX - 6, $bowY + 2))) | Out-Null
        $bowL.Points = $pcl
        $canvas.Children.Add($bowL) | Out-Null
        
        $bowR = New-Object System.Windows.Shapes.Polygon
        $bowR.Fill = $rcol
        $pcr = New-Object System.Windows.Media.PointCollection
        $pcr.Add((New-Object System.Windows.Point($centerX, $bowY + 4))) | Out-Null
        $pcr.Add((New-Object System.Windows.Point($centerX + 18, $bowY - 10))) | Out-Null
        $pcr.Add((New-Object System.Windows.Point($centerX + 6, $bowY + 2))) | Out-Null
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
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c,0.0))) | Out-Null
        $mid = $c
        $mid.A = 120
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.40))) | Out-Null
        $fade = $c
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
        
        $glow.Fill = $g
        $baseGO = 0.70 + (Rand01 / 6.0)
        $glow.Opacity = $baseGO
        
        [System.Windows.Controls.Canvas]::SetLeft($glow, $x - 9) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($glow, $y - 9) | Out-Null
        $canvas.Children.Add($glow) | Out-Null
        
        # Core
        $core = New-Object System.Windows.Shapes.Ellipse
        $core.Width = 7
        $core.Height = 7
        $core.Fill = New-Object System.Windows.Media.SolidColorBrush($c)
        $core.Opacity = 0.85
        
        [System.Windows.Controls.Canvas]::SetLeft($core, $x - 3.5) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($core, $y - 3.5) | Out-Null
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
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Colors]::White,0.0))) | Out-Null
        $mid = [System.Windows.Media.Colors]::White
        $mid.A = 110
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.35))) | Out-Null
        $fade = [System.Windows.Media.Colors]::White
        $fade.A = 0
        $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
        
        $snow.Fill = $g
        $baseO = 0.22 + (Rand01 / 6.0)
        $snow.Opacity = $baseO
        
        $x = Rand01 * $sceneW
        $y = Rand01 * $sceneH
        
        [System.Windows.Controls.Canvas]::SetLeft($snow, $x) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($snow, $y) | Out-Null
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
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($c,0.0))) | Out-Null
                $mid = $c
                $mid.A = 120
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($mid,0.40))) | Out-Null
                $fade = $c
                $fade.A = 0
                $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop($fade,1.0))) | Out-Null
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
        
        [System.Windows.Controls.Canvas]::SetLeft($s.Shape, $s.X) | Out-Null
        [System.Windows.Controls.Canvas]::SetTop($s.Shape, $s.Y) | Out-Null
        
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
        
        $st.Shape.X1 += $st.VX
        $st.Shape.Y1 += $st.VY
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

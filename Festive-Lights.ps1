Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsFormsIntegration
Add-Type -AssemblyName System.Windows.Forms

# Create the main window
$window = New-Object System.Windows.Window
$window.Title = "Twinkling Christmas Tree"
$window.Height = 600
$window.Width = 800
$window.Background = [System.Windows.Media.Brushes]::Black

# Create a Canvas to draw on
$canvas = New-Object System.Windows.Controls.Canvas
$canvas.Height = $window.Height
$canvas.Width = $window.Width
$window.Content = $canvas

# Define colors
$treeColor = [System.Windows.Media.Color]::FromRgb(0, 100, 0)
$trunkColor = [System.Windows.Media.Color]::FromRgb(139, 69, 19)
$lightColors = @(
    [System.Windows.Media.Brushes]::Red,
    [System.Windows.Media.Brushes]::Yellow,
    [System.Windows.Media.Brushes]::Blue,
    [System.Windows.Media.Brushes]::Green,
    [System.Windows.Media.Brushes]::Magenta,
    [System.Windows.Media.Brushes]::Cyan
)
$starColors = @(
    [System.Windows.Media.Brushes]::White,
    [System.Windows.Media.Brushes]::Gray,
    [System.Windows.Media.Brushes]::LightGray
)

# Tree parameters
$treeHeight = 250
$trunkHeight = 50
$trunkWidth = 80
$treeCenter = $window.Width / 2
$treeY = 50

# Global variables for lights and dots
$lights = @()
$dots = @()

# Fix for Get-Random. Now a reusable function.
function ShouldTwinkle {
    [CmdletBinding()]
    param(
        [int]$TwinkleChance = 10
    )
    return (Get-Random -Minimum 1 -Maximum ($TwinkleChance + 1)) -eq 1
}

##################################################
# Drawing Functions
##################################################

function Draw-Tree {
    # Tree body
    $treePoly = New-Object System.Windows.Shapes.Polygon
    $treePoly.Fill = $treeColor
    $treePoly.Points.Add((New-Object System.Windows.Point($treeCenter, $treeY)))
    $treePoly.Points.Add((New-Object System.Windows.Point($treeCenter - $treeHeight, $treeY + $treeHeight)))
    $treePoly.Points.Add((New-Object System.Windows.Point($treeCenter + $treeHeight, $treeY + $treeHeight)))
    $canvas.Children.Add($treePoly)

    # Trunk
    $trunkRect = New-Object System.Windows.Shapes.Rectangle
    $trunkRect.Fill = $trunkColor
    $trunkRect.Height = $trunkHeight
    $trunkRect.Width = $trunkWidth
    $trunkRect.SetValue([System.Windows.Controls.Canvas]::LeftProperty, $treeCenter - ($trunkWidth / 2))
    $trunkRect.SetValue([System.Windows.Controls.Canvas]::TopProperty, $treeY + $treeHeight)
    $canvas.Children.Add($trunkRect)
}

function Draw-Lights {
    # Clear existing lights
    $lights | ForEach-Object { $canvas.Children.Remove($_) }
    $lights = @()

    $numLights = 150
    $minX = $window.Width / 2 - $treeHeight
    $maxX = $window.Width / 2 + $treeHeight
    $minY = $treeY
    $maxY = $treeY + $treeHeight
    
    for ($i = 0; $i -lt $numLights; $i++) {
        $x = Get-Random -Minimum $minX -Maximum ($maxX + 1)
        $y = Get-Random -Minimum $minY -Maximum ($maxY + 1)
        
        # Check if the point is within the triangle
        if ($y -gt $minY + ($x - $minX) * ($maxY - $minY) / $treeHeight -and
            $y -gt $minY + ($maxX - $x) * ($maxY - $minY) / $treeHeight) {
            
            $ellipse = New-Object System.Windows.Shapes.Ellipse
            $ellipse.Width = 8
            $ellipse.Height = 8
            $ellipse.Fill = $lightColors[(Get-Random -Maximum $lightColors.Count)]
            $ellipse.SetValue([System.Windows.Controls.Canvas]::LeftProperty, $x)
            $ellipse.SetValue([System.Windows.Controls.Canvas]::TopProperty, $y)
            $canvas.Children.Add($ellipse)
            $lights += $ellipse
        }
    }
}

function Twinkle-Elements {
    # Twinkle the lights on the tree
    $lights | ForEach-Object {
        if (ShouldTwinkle) {
            $_.Fill = $lightColors[(Get-Random -Maximum $lightColors.Count)]
        }
    }
    
    # Twinkle the dots
    $dots | ForEach-Object {
        if (ShouldTwinkle) {
            $_.Fill = $starColors[(Get-Random -Maximum $starColors.Count)]
        }
    }
}

function Draw-Dots {
    $numDots = 200
    for ($i = 0; $i -lt $numDots; $i++) {
        $x = Get-Random -Maximum ($window.Width + 1)
        $y = Get-Random -Maximum ($window.Height + 1)

        # Don't draw dots in the tree area
        $isInsideTree = ($y -gt $treeY + ($x - ($treeCenter - $treeHeight)) -and
                         $y -lt $treeY + $treeHeight -and
                         $y -gt $treeY + ($treeCenter + $treeHeight - $x) -and
                         $y -lt $treeY + $treeHeight)
        
        if (-not $isInsideTree) {
            $ellipse = New-Object System.Windows.Shapes.Ellipse
            $ellipse.Width = 2
            $ellipse.Height = 2
            $ellipse.Fill = $starColors[(Get-Random -Maximum $starColors.Count)]
            $ellipse.SetValue([System.Windows.Controls.Canvas]::LeftProperty, $x)
            $ellipse.SetValue([System.Windows.Controls.Canvas]::TopProperty, $y)
            $canvas.Children.Add($ellipse)
            $dots += $ellipse
        }
    }
}

##################################################
# Main Logic
##################################################

# Initial drawing
Draw-Tree
Draw-Lights
Draw-Dots

# Timer for twinkling effect
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(100)

$script:frame = 0
$timer.Add_Tick({
    # Twinkle lights and dots
    Twinkle-Elements
    $script:frame++
})

$timer.Start()

# Show the window and start the application's message loop
$app = New-Object System.Windows.Application
$app.Run($window)

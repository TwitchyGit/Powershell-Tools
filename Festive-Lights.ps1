param(
    [int]$TreeHeight = 21, # The height of the tree's branches
    [int]$TrunkWidth = 8, # The width of the tree's trunk
    [int]$TrunkHeight = 4, # The height of the tree's trunk
    [int]$XPos = 50, # The starting x position for centering the tree
    [array]$colors = @("red", "yellow", "blue", "green", "magenta"),
    [int]$count = 100, # Number of frames to run the animation
    [int]$duration = 250, # ms delay per frame
    [int]$LightYOffset = 15, # Vertical offset for the lights
    [int]$LightAmplitude = 3, # How much the lights "sag"
    [int]$LightFrequency = 10 # How often the lights are pinned
)

# Function to draw the entire scene
function Draw-Scene {
    param(
        [int]$Iteration,
        [string]$TreeColor
    )

    # 1. Draw the scrolling lights first so they appear "behind" the tree
    for ($i = 0; $i -lt 100; $i++) {
        # Calculate the y-position of the light using a sine wave
        # This creates the repeating "pinned" sagging effect
        $waveValue = [math]::sin($i / $LightFrequency * [math]::PI) * $LightAmplitude
        $y = [int]($LightYOffset + $waveValue)

        # The X position is determined by a scrolling offset
        $x = [int](($i - $Iteration) + ($host.ui.rawui.windowsize.width / 2))

        # Only draw if the light is on screen
        if ($x -ge 0 -and $x -lt $host.ui.rawui.windowsize.width) {
            # Use a modulo to loop through the colors for the light string
            $color = $colors[($i + $Iteration) % $colors.Length]
            [Console]::SetCursorPosition($x, $y)
            Write-Host "o" -ForegroundColor $color -NoNewline
        }
    }

    # 2. Draw the tree on top
    
    # Set cursor to the top of the screen to draw the text
    [Console]::SetCursorPosition(0, 0)
    Write-Host "`n`t`t`tMerry Christmas" -foregroundColor yellow
    Write-Host "`t`t`t       &" -foregroundColor yellow
    Write-Host "`t`t`t Happy New Year" -foregroundColor yellow
    Write-Host "`n"

    # Set cursor to the starting position of the tree branches
    [Console]::SetCursorPosition(0, 5)
    
    # Draw the tree branches
    for ( $i = 1; $i -le $TreeHeight; $i++ ) {
        $line = " " * ($XPos - $i) + "*" * ($i * 2)
        Write-Host $line -foregroundColor $TreeColor
    }

    # Draw the tree base
    $baseWidth = $TrunkWidth + 2
    $baseStart = $XPos - ($baseWidth / 2)
    $line = " " * $baseStart + "/" + "_" * ($baseWidth - 2) + "\"
    Write-Host $line -ForegroundColor $TreeColor

    # Draw the tree trunk (now part of the base)
    for ( $j = 1; $j -le $TrunkHeight; $j++ ){
        $line = " " * ($XPos - ($TrunkWidth / 2)) + "#" * $TrunkWidth
        Write-Host $line -foregroundColor $TreeColor
    }
}

# Main animation loop
do {
    Clear-Host

    # Choose a new random color for the tree and trunk at each step
    $Idx = (Get-Random -Min 0 -Max ($colors.Length - 1))
    $currentColor = $colors[$Idx]

    # Draw the complete scene
    Draw-Scene -Iteration $_ -TreeColor $currentColor

    # Pause for a moment
    Start-Sleep -milliseconds $duration

    # Decrement the counter to end the loop
    $count--
} while ($count -gt 0)

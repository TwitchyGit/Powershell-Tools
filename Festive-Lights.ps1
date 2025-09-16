param(
    [int]$TreeHeight = 21,
    [int]$TrunkWidth = 8,
    [int]$TrunkHeight = 4,
    [int]$XPos = 50,
    [array]$colors = @("red", "yellow", "blue", "green", "magenta", "cyan"),
    [int]$count = 200,
    [int]$duration = 100, # ms delay per frame
    [int]$LightYOffset = 15,
    [int]$LightAmplitude = 3,
    [int]$LightFrequency = 10,
    [array]$StarColors = @("white", "gray", "silver")
)

# Function to draw the stationary parts of the scene (tree, base, text)
function Draw-StationaryScene {
    param(
        [string]$MessageColor,
        [string]$TreeColor
    )
    
    # Write the holiday message
    [Console]::SetCursorPosition(0,0)
    Write-Host "`n`t`t`tMerry Christmas" -foregroundColor $MessageColor
    Write-Host "`t`t`t       &" -foregroundColor $MessageColor
    Write-Host "`t`t`t Happy New Year" -foregroundColor $MessageColor
    Write-Host "`n"

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

# Function to update the animated parts (twinkling and scrolling)
function Update-AnimatedElements {
    param(
        [int]$Iteration
    )
    
    # Get console window width
    $winWidth = $host.ui.rawui.windowsize.width

    # 1. Draw the scrolling lights on both sides of the tree
    $lightStringCount = 3 # Number of light strings
    for ($k = 0; $k -lt $lightStringCount; $k++) {
        $stringOffset = ($k - 1) * 5 # A slight vertical offset for each string

        for ($i = 0; $i -lt 100; $i++) {
            # Calculate the y-position with a sine wave
            $waveValue = [math]::sin($i / $LightFrequency * [math]::PI) * $LightAmplitude
            $y = [int]($LightYOffset + $waveValue + $stringOffset)

            # Left side
            $xLeft = [int]($i - $Iteration)
            if ($xLeft -ge 0 -and $xLeft -lt $XPos - 5) { # Stop before the tree
                $colorIndex = Get-Random -Maximum $colors.Length
                $color = $colors[$colorIndex]
                [Console]::SetCursorPosition($xLeft, $y)
                Write-Host "o" -ForegroundColor $color -NoNewline
            }

            # Right side
            $xRight = [int](($i - $Iteration) + ($winWidth / 2))
            if ($xRight -gt $XPos + 5 -and $xRight -lt $winWidth) { # Start after the tree
                $colorIndex = Get-Random -Maximum $colors.Length
                $color = $colors[$colorIndex]
                [Console]::SetCursorPosition($xRight, $y)
                Write-Host "o" -ForegroundColor $color -NoNewline
            }
        }
    }

    # 2. Add some twinkling stars/dots
    $dotsCount = 20
    for ($i = 0; $i -lt $dotsCount; $i++) {
        # Randomly decide to change a dot's color
        if (Get-Random -Minimum 1 -Maximum 10 -eq 1) {
            # Random position
            $y = Get-Random -Minimum 5 -Maximum 25
            $x = Get-Random -Minimum 0 -Maximum $winWidth
            
            # Ensure the dot doesn't appear on the tree itself
            $treeSpan = $XPos - $TreeHeight..($XPos + $TreeHeight)
            if ($y -gt 5 -and $y -lt ($TreeHeight + 5) -and ($x -gt ($XPos - $y) -and $x -lt ($XPos + $y))) {
                continue # Skip if the position is within the tree
            }

            $starColorIndex = Get-Random -Maximum $StarColors.Length
            $starColor = $StarColors[$starColorIndex]
            [Console]::SetCursorPosition($x, $y)
            Write-Host "." -ForegroundColor $starColor -NoNewline
        }
    }

    # 3. Add twinkling lights to the tree itself
    $treeX = $XPos
    $treeY = 5 # Starting Y position for the tree
    for ($y = 0; $y -lt $TreeHeight; $y++) {
        # Loop through a few potential points to twinkle
        for ($i = 0; $i -lt 3; $i++) {
            if (Get-Random -Minimum 1 -Maximum 10 -eq 1) {
                # Calculate the X position within the tree's boundaries
                $leftBound = $treeX - ($y + 1)
                $rightBound = $treeX + ($y + 1)
                $x = Get-Random -Minimum ($leftBound) -Maximum ($rightBound)

                # Set the cursor and change the color of the star
                [Console]::SetCursorPosition($x, $treeY + $y)
                $lightColorIndex = Get-Random -Maximum $colors.Length
                $lightColor = $colors[$lightColorIndex]
                Write-Host "*" -ForegroundColor $lightColor -NoNewline
            }
        }
    }
}

# Main animation loop
# Draw the stationary scene once at the beginning
Clear-Host
Draw-StationaryScene -MessageColor yellow -TreeColor "DarkGreen"

do {
    # Only update the animated elements in each loop
    Update-AnimatedElements -Iteration $_
    
    # Pause for a moment
    Start-Sleep -milliseconds $duration
    
    # Decrement the counter to end the loop
    $count--
} while ($count -gt 0)

# Final cleanup
[Console]::SetCursorPosition(0, 30) # Move cursor to a safe place
Write-Host ""

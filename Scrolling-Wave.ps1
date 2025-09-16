# Define the screen width. Adjust this for your console size.
$ScreenWidth = 80

# The number of steps to iterate through, which determines the length of the animation.
$MaxSteps = 1000

# The base speed of the animation. Lower values are faster.
$DelayMilliseconds = 50

# A variable to hold the random height multiplier.
$RandomHeight = 1

# Iterate to create the animation
0..$MaxSteps | ForEach-Object {

    # Check if a new random height should be generated
    if ($_ % 50 -eq 0) {
        # Generate a new random height between 10 and 30
        $RandomHeight = Get-Random -Minimum 10 -Maximum 30
    }

    # Calculate the value, adjusted for the current step and the random height
    $Value = [int]($RandomHeight * [math]::sin(($_ + $RandomHeight) / 5))

    # Calculate the starting position for the line to create a right-to-left scroll
    $StartPosition = $ScreenWidth - $Value - 1

    # Ensure the start position is not a negative number
    if ($StartPosition -lt 0) {
        $StartPosition = 0
    }

    # Create the line by adding spaces and then asterisks
    $Line = (" " * $StartPosition) + "*"

    # Clear the current line before writing the new one to prevent leftover characters
    Write-Host -NoNewline "`r$Line"
    
    # Pause for a short duration to control the animation speed
    Start-Sleep -milliseconds $DelayMilliseconds
}

# Add a final newline character to clean up the console after the script finishes
Write-Host ""

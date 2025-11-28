# Define the screen width. Adjust this for your console size.
$ScreenWidth = 80

# The number of steps to iterate through, which determines the length of the animation.
$MaxSteps = 1000

# The base speed of the animation. Lower values are faster.
$DelayMilliseconds = 50

# An array to hold the heights of the mountain columns
# Initialize it with random values to start with a landscape
$MountainHeights = @()
for ($i = 0; $i -lt $ScreenWidth; $i++) {
    $MountainHeights += Get-Random -Minimum 1 -Maximum 20
}

# Iterate to create the animation
0..$MaxSteps | ForEach-Object {
    
    # Add a new random height to the end of the array
    # This creates a new mountain column on the right side
    $NewHeight = Get-Random -Minimum 1 -Maximum 20
    $MountainHeights += $NewHeight

    # Remove the first height from the array
    # This simulates the scrolling to the left
    $MountainHeights = $MountainHeights | Select-Object -Skip 1

    # Clear the screen (or the current line) to prevent drawing over previous output
    Clear-Host

    # Build the line to be displayed
    $DisplayLine = ""
    foreach ($Height in $MountainHeights) {
        $DisplayLine += "*" * $Height
        $DisplayLine += " "
    }

    # Display the mountain range
    Write-Host $DisplayLine

    # Pause for a short duration to control the animation speed
    Start-Sleep -milliseconds $DelayMilliseconds
}

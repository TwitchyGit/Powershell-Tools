<#
.SYNOPSIS
    Check an AD Account if disabled/error locked out.

.DESCRIPTION
    Script : Check-AD-User.ps1
    Source : tbc
    Dist To: CyberArk JumpServer managing Account Monitor
    Run As : Logged in User
#>

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

#region Configuration
$Environment = "DEV"  # Change to "PROD" for production domains

$DomainArrays = @{
    "DEV"  = @("QAASIAPAC", "QAEUROPE", "QAAMERICAS", "QAJAPAN")
    "PROD" = @("ASIAPAC", "EUROPE", "AMERCIAS", "JAPAN")
}

$ColorScheme = @{
    Background      = "#2D2D30"
    LightText       = "#E0E0E0"
    AccentTeal      = "#4ECDCC"
    AccentRed       = "#FF6B6B"
    SuccessGreen    = "#95E1D3"
    DarkGray        = "#555555"
    InputDark       = "#3C3C3C"
    InputDarker     = "#282828"
    ButtonBlueDark  = "#1E5A8C"
    ButtonBlueLight = "#4682B4"
}
#endregion

#region Helper Functions

<#
.SYNOPSIS
    Converts UserAccountControl integer value to readable flag names.
.DESCRIPTION
    Takes a UAC bitmask value and returns an array of active flags with their names.
    Used to interpret Active Directory account control settings.
#>
function GetUserAccountControlFlag {
    param([int]$UACValue)
    
    $UACFlags = @{
        1        = "SCRIPT"
        2        = "ACCOUNTDISABLE"
        8        = "HOMEDIR_REQUIRED"
        16       = "LOCKOUT"
        32       = "PASSWD_NOTREQD"
        64       = "PASSWD_CANT_CHANGE"
        128      = "ENCRYPTED_TEXT_PWD_ALLOWED"
        256      = "TEMP_DUPLICATE_ACCOUNT"
        512      = "NORMAL_ACCOUNT"
        2048     = "INTERDOMAIN_TRUST_ACCOUNT"
        4096     = "WORKSTATION_TRUST_ACCOUNT"
        8192     = "SERVER_TRUST_ACCOUNT"
        65536    = "DONT_EXPIRE_PASSWORD"
        131072   = "MNS_LOGON_ACCOUNT"
        262144   = "SMARTCARD_REQUIRED"
        524288   = "TRUSTED_FOR_DELEGATION"
        1048576  = "NOT_DELEGATED"
        2097152  = "USE_DES_KEY_ONLY"
        4194304  = "DONT_REQ_PREAUTH"
        8388608  = "PASSWORD_EXPIRED"
        16777216 = "TRUSTED_TO_AUTH_FOR_DELEGATION"
        67108864 = "PARTIAL_SECRETS_ACCOUNT"
    }
    
    $ActiveFlags = @()
    foreach ($flag in $UACFlags.Keys) {
        if ($UACValue -band $flag) {
            $ActiveFlags += "$flag - $($UACFlags[$flag])"
        }
    }
    return $ActiveFlags
}

<#
.SYNOPSIS
    Formats Active Directory group membership into a readable numbered list.
.DESCRIPTION
    Extracts common names from Distinguished Names and formats them as a sorted,
    numbered list for display. Returns a message if no groups are found.
#>
function FormatGroupMembership {
    param($memberOf)
    
    if (-not $memberOf -or $memberOf.Count -eq 0) {
        return "No group memberships found"
    }
    
    $groupList = $memberOf | ForEach-Object {
        if ($_ -match "CN=([^,]*)") {
            $matches[1]
        } else {
            $_
        }
    } | Sort-Object
    
    $groupOutput = for ($i = 0; $i -lt $groupList.Count; $i++) {
        " $($i + 1). $($groupList[$i])"
    }
    
    return ($groupOutput -join "`n")
}

<#
.SYNOPSIS
    Formats complete AD user information into a structured text report.
.DESCRIPTION
    Takes an AD user object and domain name, then returns a formatted string
    containing all user properties organized into logical sections with headers.
#>
function FormatUserInfo {
    param($user, $domain)
    
    $groupMembership = FormatGroupMembership -memberOf $user.MemberOf
    
    return @"
$("=" * 70)
DOMAIN: $domain
$("=" * 70)

ACCOUNT INFORMATION
$("-" * 50)
Display Name:           $($user.DisplayName)
Distinguished Name:     $($user.DistinguishedName)
User Principal Name:    $($user.UserPrincipalName)
Email:                  $($user.EmailAddress)

PASSWORD STATUS
$("-" * 50)
Password Expired:       $($user.PasswordExpired)
Password Never Expires: $($user.PasswordNeverExpires)
Password Not Required:  $($user.PasswordNotRequired)
Cannot Change Password: $($user.CannotChangePassword)
Password Last Set:      $(if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss") } else { "Must change password at next logon" })

ACCOUNT STATUS
$("-" * 50)
Enabled:                $($user.Enabled)
Locked Out:             $($user.LockedOut)
Account Expiration Date: $(if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" })
Account Lockout Time:   $($user.AccountLockoutTime)
User Account Control:   $(if ($user.UserAccountControl) { GetUserAccountControlFlag $user.UserAccountControl })

ORGANIZATIONAL INFORMATION
$("-" * 50)
Department:             $($user.Department)
Title:                  $($user.Title)
Manager:                $($user.Manager)
Office:                 $($user.Office)
Phone:                  $($user.OfficePhone)

TIMESTAMPS
$("-" * 50)
Created:                $(if ($user.Created) { $user.Created.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" })
Last Logon:             $(if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" })

GROUP MEMBERSHIPS ($($user.MemberOf.Count) groups)
$("-" * 50)
$groupMembership
"@
}
#endregion

#region UI Helper Functions

<#
.SYNOPSIS
    Creates a configured DropShadowEffect for WPF controls.
.DESCRIPTION
    Generates a drop shadow effect with customizable direction, depth, blur,
    and opacity. Used to add 3D depth to UI elements in the dark theme.
#>
function New-DropShadowEffect {
    param(
        [int]$Direction = 315,
        [double]$ShadowDepth = 2,
        [double]$BlurRadius = 3,
        [double]$Opacity = 0.8
    )
    
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $shadow.Direction = $Direction
    $shadow.ShadowDepth = $ShadowDepth
    $shadow.BlurRadius = $BlurRadius
    $shadow.Opacity = $Opacity
    return $shadow
}

<#
.SYNOPSIS
    Creates a linear gradient brush from hex color values.
.DESCRIPTION
    Generates a WPF LinearGradientBrush with two color stops from hex strings.
    Used to create smooth color transitions for backgrounds and buttons.
#>
function New-GradientBrush {
    param(
        [string]$StartColor,
        [string]$EndColor,
        [string]$StartPoint = "0,0",
        [string]$EndPoint = "0,1"
    )
    
    $gradient = New-Object System.Windows.Media.LinearGradientBrush
    $gradient.StartPoint = $StartPoint
    $gradient.EndPoint = $EndPoint
    
    $stop1 = New-Object System.Windows.Media.GradientStop
    $stop1.Color = [System.Windows.Media.Color]::FromRgb(
        [convert]::ToInt32($StartColor.Substring(1,2), 16),
        [convert]::ToInt32($StartColor.Substring(3,2), 16),
        [convert]::ToInt32($StartColor.Substring(5,2), 16)
    )
    $stop1.Offset = 0
    
    $stop2 = New-Object System.Windows.Media.GradientStop
    $stop2.Color = [System.Windows.Media.Color]::FromRgb(
        [convert]::ToInt32($EndColor.Substring(1,2), 16),
        [convert]::ToInt32($EndColor.Substring(3,2), 16),
        [convert]::ToInt32($EndColor.Substring(5,2), 16)
    )
    $stop2.Offset = 1
    
    $gradient.GradientStops.Add($stop1)
    $gradient.GradientStops.Add($stop2)
    
    return $gradient
}

<#
.SYNOPSIS
    Creates a styled WPF Label control with consistent formatting.
.DESCRIPTION
    Generates a pre-configured Label with dark theme styling, positioning,
    and common properties. Reduces code duplication for label creation.
#>
function New-StyledLabel {
    param(
        [string]$Content,
        [string]$Foreground = $ColorScheme.LightText,
        [int]$Row,
        [int]$Column = 0,
        [int]$ColumnSpan = 1,
        [string]$Margin = "10,5,5,5",
        [string]$FontWeight = "Normal",
        [int]$FontSize = 12,
        [string]$HorizontalAlignment = "Left"
    )
    
    $label = New-Object System.Windows.Controls.Label
    $label.Content = $Content
    $label.Foreground = $Foreground
    $label.Margin = $Margin
    $label.FontWeight = $FontWeight
    $label.FontSize = $FontSize
    $label.HorizontalAlignment = $HorizontalAlignment
    $label.VerticalAlignment = "Center"
    
    [System.Windows.Controls.Grid]::SetRow($label, $Row)
    [System.Windows.Controls.Grid]::SetColumn($label, $Column)
    if ($ColumnSpan -gt 1) {
        [System.Windows.Controls.Grid]::SetColumnSpan($label, $ColumnSpan)
    }
    
    return $label
}

<#
.SYNOPSIS
    Creates a styled WPF TextBox control with dark theme effects.
.DESCRIPTION
    Generates a pre-configured TextBox with gradient background, drop shadow,
    and consistent styling. Used for input fields in the interface.
#>
function New-StyledTextBox {
    param(
        [int]$Row,
        [int]$Column = 1,
        [string]$Margin = "5,5,10,5",
        [int]$Height = 25
    )
    
    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Margin = $Margin
    $textBox.Height = $Height
    $textBox.VerticalContentAlignment = "Center"
    $textBox.BorderThickness = "2"
    $textBox.BorderBrush = $ColorScheme.DarkGray
    $textBox.Foreground = $ColorScheme.LightText
    $textBox.Effect = New-DropShadowEffect
    $textBox.Background = New-GradientBrush -StartColor $ColorScheme.InputDark -EndColor $ColorScheme.InputDarker
    
    [System.Windows.Controls.Grid]::SetRow($textBox, $Row)
    [System.Windows.Controls.Grid]::SetColumn($textBox, $Column)
    
    return $textBox
}

<#
.SYNOPSIS
    Creates a styled WPF Button control with gradient and shadow effects.
.DESCRIPTION
    Generates a pre-configured Button with custom gradient colors, drop shadow,
    and consistent styling. Used for action buttons in the interface.
#>
function New-StyledButton {
    param(
        [string]$Content,
        [int]$Row,
        [int]$ColumnSpan = 2,
        [int]$Width = 120,
        [int]$Height = 35,
        [string]$Margin = "0,10,0,10",
        [string]$StartColor,
        [string]$EndColor,
        [string]$BorderColor
    )
    
    $button = New-Object System.Windows.Controls.Button
    $button.Content = $Content
    $button.Width = $Width
    $button.Height = $Height
    $button.HorizontalAlignment = "Center"
    $button.Margin = $Margin
    $button.FontWeight = "Bold"
    $button.Foreground = "#FFFFFF"
    $button.Background = New-GradientBrush -StartColor $StartColor -EndColor $EndColor
    $button.BorderThickness = "2"
    $button.BorderBrush = $BorderColor
    $button.Effect = New-DropShadowEffect -ShadowDepth 3 -BlurRadius 4
    
    [System.Windows.Controls.Grid]::SetRow($button, $Row)
    [System.Windows.Controls.Grid]::SetColumnSpan($button, $ColumnSpan)
    
    return $button
}

<#
.SYNOPSIS
    Creates a styled WPF ComboBox control with items and hover effects.
.DESCRIPTION
    Generates a pre-configured ComboBox populated with items, custom styling,
    and mouse hover effects. Used for dropdown selections in the interface.
#>
function New-StyledComboBox {
    param(
        [int]$Row,
        [int]$Column = 1,
        [array]$Items,
        [string]$Margin = "5,5,10,5",
        [int]$Height = 25
    )
    
    $comboBox = New-Object System.Windows.Controls.ComboBox
    $comboBox.Margin = $Margin
    $comboBox.Height = $Height
    $comboBox.VerticalContentAlignment = "Center"
    $comboBox.BorderThickness = "2"
    $comboBox.BorderBrush = $ColorScheme.DarkGray
    $comboBox.Foreground = $ColorScheme.AccentRed
    $comboBox.IsReadOnly = $true
    $comboBox.Effect = New-DropShadowEffect
    $comboBox.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(40, 40, 40)
    )
    
    foreach ($item in $Items) {
        $comboBoxItem = New-Object System.Windows.Controls.ComboBoxItem
        $comboBoxItem.Content = $item
        $comboBoxItem.Foreground = $ColorScheme.AccentRed
        $comboBoxItem.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.Color]::FromRgb(60, 60, 60)
        )
        
        $comboBoxItem.Add_MouseEnter({
            $this.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(80, 80, 80)
            )
        })
        $comboBoxItem.Add_MouseLeave({
            $this.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.Color]::FromRgb(60, 60, 60)
            )
        })
        
        $comboBox.Items.Add($comboBoxItem) | Out-Null
    }
    
    $comboBox.SelectedIndex = 0
    
    [System.Windows.Controls.Grid]::SetRow($comboBox, $Row)
    [System.Windows.Controls.Grid]::SetColumn($comboBox, $Column)
    
    return $comboBox
}
#endregion

#region Main Script
# Verify Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Active Directory module is not available. Please install RSAT tools.",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

# Create main window
$window = New-Object System.Windows.Window
$window.Title = "AD User Information Lookup - $Environment Environment"
$window.Width = 700
$window.Height = 650
$window.MinWidth = 500
$window.MinHeight = 450
$window.WindowStartupLocation = "CenterScreen"
$window.ResizeMode = "CanResize"
$window.Background = $ColorScheme.Background

# Create and configure grid
$grid = New-Object System.Windows.Controls.Grid
$window.Content = $grid

# Define grid structure
$rowHeights = @("Auto", "Auto", "Auto", "Auto", "Auto", "Auto", "*", "Auto")
foreach ($height in $rowHeights) {
    $rowDef = New-Object System.Windows.Controls.RowDefinition
    $rowDef.Height = $height
    $grid.RowDefinitions.Add($rowDef) | Out-Null
}

$grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = "120" }))
$grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))

# Add UI controls
$titleLabel = New-StyledLabel -Content "Active Directory User Lookup" `
    -Row 0 -ColumnSpan 2 -FontSize 16 -FontWeight "Bold" `
    -HorizontalAlignment "Center" -Margin "0,10,0,5"
$grid.Children.Add($titleLabel)

$envLabel = New-StyledLabel -Content "Environment: $Environment" `
    -Row 1 -ColumnSpan 2 -FontSize 12 -FontWeight "Bold" `
    -HorizontalAlignment "Center" -Margin "0,0,0,10" `
    -Foreground $(if ($Environment -eq "PROD") { $ColorScheme.AccentRed } else { $ColorScheme.AccentTeal })
$grid.Children.Add($envLabel)

$usernameLabel = New-StyledLabel -Content "Username:" -Row 2 -Column 0
$grid.Children.Add($usernameLabel)

$usernameTextBox = New-StyledTextBox -Row 2 -Column 1
[System.Windows.Controls.Grid]::SetColumnSpan($usernameTextBox, 1)
$grid.Children.Add($usernameTextBox)

$searchButton = New-StyledButton -Content "Search User" -Row 3 `
    -StartColor "#4682B4" -EndColor "#1E5A8C" -BorderColor "#4682B0"
$grid.Children.Add($searchButton)

$statusLabel = New-StyledLabel -Content "Ready to search ... " `
    -Row 4 -ColumnSpan 2 -HorizontalAlignment "Center" `
    -Foreground $ColorScheme.AccentTeal -Margin "0,5,0,5"
$grid.Children.Add($statusLabel)

$resultsLabel = New-StyledLabel -Content "Results:" -Row 5 `
    -ColumnSpan 2 -FontWeight "Bold" -Margin "10,5,5,0"
$grid.Children.Add($resultsLabel)

# Output text box (requires custom styling)
$outputTextBox = New-Object System.Windows.Controls.TextBox
$outputTextBox.Margin = "10,5,10,10"
$outputTextBox.IsReadOnly = $true
$outputTextBox.VerticalScrollBarVisibility = "Auto"
$outputTextBox.HorizontalScrollBarVisibility = "Auto"
$outputTextBox.FontFamily = "Consolas"
$outputTextBox.FontSize = 11
$outputTextBox.AcceptsReturn = $true
$outputTextBox.TextWrapping = "NoWrap"
$outputTextBox.BorderThickness = "3"
$outputTextBox.BorderBrush = $ColorScheme.DarkGray
$outputTextBox.Foreground = $ColorScheme.LightText
$outputTextBox.Effect = New-DropShadowEffect -Direction 135 -ShadowDepth 3 -BlurRadius 5 -Opacity 0.6
$outputTextBox.Background = New-GradientBrush -StartColor "#191919" -EndColor "#232323"
[System.Windows.Controls.Grid]::SetRow($outputTextBox, 6)
[System.Windows.Controls.Grid]::SetColumnSpan($outputTextBox, 2)
$grid.Children.Add($outputTextBox)

$clearButton = New-StyledButton -Content "Clear Results" -Row 7 `
    -Width 120 -Height 30 -Margin "0,5,0,10" `
    -StartColor "#DC5050" -EndColor "#B42828" -BorderColor "#CD5C5C"
$grid.Children.Add($clearButton)

#endregion

#region Event Handlers
$searchButton.Add_Click({
    $username = $usernameTextBox.Text.Trim()
    
    if ([string]::IsNullOrEmpty($username)) {
        $statusLabel.Content = "Please enter a username"
        $statusLabel.Foreground = $ColorScheme.AccentRed
        return
    }
    
    $statusLabel.Content = "Searching across all domains in $Environment environment..."
    $statusLabel.Foreground = $ColorScheme.AccentTeal
    $searchButton.IsEnabled = $false
    $outputTextBox.Text = ""
    
    $foundDomains = @()
    $allResults = @()
    $searchErrors = @()
    
    $adProperties = @(
        'DisplayName', 'DistinguishedName', 'UserPrincipalName', 'EmailAddress',
        'Enabled', 'LockedOut', 'AccountExpirationDate', 'AccountLockoutTime',
        'UserAccountControl', 'PasswordExpired', 'PasswordNeverExpires',
        'PasswordNotRequired', 'CannotChangePassword', 'PasswordLastSet',
        'Department', 'Title', 'Manager', 'Office', 'OfficePhone',
        'Created', 'LastLogonDate', 'MemberOf'
    )
    
    # Search each domain
    foreach ($domain in $DomainArrays[$Environment]) {
        try {
            $server = "$($domain).NOM"
            $statusLabel.Content = "Searching in $domain..."
            
            $user = Get-ADUser -Identity $username -Server $server `
                -Properties $adProperties -ErrorAction Stop
            
            $foundDomains += $domain
            $allResults += @{
                Domain = $domain
                User = $user
            }
        } catch {
            # User not found or other error in this domain - continue searching
            $searchErrors += @{
                Domain = $domain
                Error = $_.Exception.Message
            }
        }
    }
    
    # Display results
    if ($foundDomains.Count -gt 0) {
        $output = ""
        
        foreach ($result in $allResults) {
            if ($output -ne "") {
                $output += "`n`n"
            }
            $output += FormatUserInfo -user $result.User -domain $result.Domain
        }
        
        $outputTextBox.Text = $output
        
        if ($foundDomains.Count -eq 1) {
            $statusLabel.Content = "User found in: $($foundDomains -join ', ')"
        } else {
            $statusLabel.Content = "User found in multiple domains: $($foundDomains -join ', ')"
        }
        $statusLabel.Foreground = $ColorScheme.SuccessGreen
    } else {
        # Not found in any domain
        $errorSummary = "User '$username' was not found in any domain.`n`n"
        $errorSummary += "Searched domains: $($DomainArrays[$Environment] -join ', ')`n"
        $errorSummary += "Environment: $Environment`n`n"
        $errorSummary += "Domain-specific errors:`n"
        $errorSummary += $("-" * 50) + "`n"
        
        foreach ($err in $searchErrors) {
            $errorSummary += "[$($err.Domain)]: $($err.Error)`n"
        }
        
        $outputTextBox.Text = $errorSummary
        $statusLabel.Content = "User not found in any domain"
        $statusLabel.Foreground = $ColorScheme.AccentRed
    }
    
    $searchButton.IsEnabled = $true
})

$clearButton.Add_Click({
    $outputTextBox.Text = ""
    $statusLabel.Content = "Results cleared - ready to search ... "
    $statusLabel.Foreground = $ColorScheme.AccentTeal
})

$usernameTextBox.Add_KeyDown({
    if ($_.Key -eq "Return") {
        $searchButton.RaiseEvent(
            (New-Object System.Windows.RoutedEventArgs(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        )
    }
})
#endregion

# Show window
$window.ShowDialog() | Out-Null

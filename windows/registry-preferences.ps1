function Set-RegistryValue {
    Param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        $parentPath = Split-Path -Path $Path
        if (-not (Test-Path $parentPath)) {
            New-Item -Path $parentPath -Force | Out-Null
        }
        switch ($Type) {
            "DWord" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop }
            "String" { Set-ItemProperty -Path $Path -Name $Name -Value "$Value" -Force -ErrorAction Stop }
            "Binary" { Set-ItemProperty -Path $Path -Name $Name -Value ([byte[]]$Value) -Force -ErrorAction Stop }
        }
    } catch {}
}

# Set app and system to use light theme
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

# Disable Bing Search in Start Menu
Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -Type "DWord"
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search\WebSearch" -Name "BingSearchEnabled" -Value 0

# Set Initial Keyboard Indicators (NumLock, CapsLock, ScrollLock) to off for current and default users
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0
Set-RegistryValue -Path "HKU\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0

# Disable verbose status messages during startup/shutdown
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 0

# Hide Recommended section in Start Menu
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideRecommendedSection" -Value 1

# Set environment to education mode
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Education" -Name "IsEducationEnvironment" -Value 1

# Disable Window Arrangement (Snap Assist) features
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "WindowArrangementActive" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0

# Set mouse speed and acceleration thresholds to 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value 0

# Show hidden files
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1

# Show file extensions
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

# Set Search Box Taskbar Mode to hidden
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0

# Hide Task View button
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0

# Set Taskbar Alignment to left
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Taskbar" -Name "TaskbarAl" -Value 0

# Set Taskbar Position to Top
$taskbarSettings = @(
    0x28,0x00,0x00,0x00,0xFF,0xFF,0xFF,0xFF,0x02,0x00,0x00,0x00,0x01,0x00,0x00,0x00,
    0x3E,0x00,0x00,0x00,0x2E,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
)
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" -Name "Settings" -Value $taskbarSettings -Type "Binary"

# Remove Widget button from taskbar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Taskbar" -Name "TaskbarDa" -Value 0

# Disable emoticon display for crash control (Blue Screen of Death)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "DisplayParameters" -Value 1

# Disable Windows Key combinations
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableLockWorkstation" -Value 1
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoWinKeys" -Value 1
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoLeftWindows" -Value 1
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoRightWindows" -Value 1

# Set WezTerm config path
Set-RegistryValue -Path "HKCU:\Environment" -Name "WEZTERM_CONFIG_FILE" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\modules\wezterm\config\wezterm.lua" -Type "String"

# Set GlazeWM config path
Set-RegistryValue -Path "HKCU:\Environment" -Name "GLAZEWM_CONFIG_PATH" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\programs\glazewm\config.yaml" -Type "String"

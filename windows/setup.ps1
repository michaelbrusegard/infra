if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires administrator privileges. Please re-run as Administrator."
    if ($Host.Name -eq "ConsoleHost") {
        Read-Host "Press Enter to exit"
    }
    Exit
}

$wslWallpaperPath = "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\assets\wallpapers\twilight-peaks.png"
$localWallpaperDir = Join-Path -Path $env:USERPROFILE -ChildPath "Pictures\Wallpapers"
$localWallpaperPath = Join-Path -Path $localWallpaperDir -ChildPath "twilight-peaks.png"

if (Test-Path $wslWallpaperPath) {
    if (-not (Test-Path $localWallpaperDir)) {
        New-Item -Path $localWallpaperDir -ItemType Directory -Force | Out-Null
    }
    Write-Host "Copying wallpaper from WSL to $localWallpaperPath..."
    Copy-Item -Path $wslWallpaperPath -Destination $localWallpaperPath -Force
} else {
    Write-Warning "Wallpaper source file not found at $wslWallpaperPath. Skipping wallpaper setup."
}

function Set-RegistryValue {
    Param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        switch ($Type) {
            "DWord" {
                Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop
                Write-Host "Set $Path\$Name to $Value (DWord)"
            }
            "String" {
                Set-ItemProperty -Path $Path -Name $Name -Value "$Value" -Type String -Force -ErrorAction Stop
                Write-Host "Set $Path\$Name to $Value (String)"
            }
            "Binary" {
                Set-ItemProperty -Path $Path -Name $Name -Value ([byte[]]$Value) -Type Binary -Force -ErrorAction Stop
                Write-Host "Set $Path\$Name to Binary Value"
            }
        }
    } catch {
        Write-Error "Failed to set registry value '$Name' at path '$Path'. Error: $_"
    }
}

function Set-Wallpaper {
    param(
        [string]$WallpaperPath,
        [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
        [string]$Style = 'Fill'
    )

    if (-not (Test-Path $WallpaperPath)) {
        Write-Error "Wallpaper file not found: $WallpaperPath"
        return
    }

    $WallpaperStyle = switch ($Style) {
        'Fill'    { 10 }
        'Fit'     { 6 }
        'Stretch' { 2 }
        'Tile'    { 1 }
        'Center'  { 0 }
        'Span'    { 22 }
    }

    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value $WallpaperStyle -Type "String"
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value $(if ($Style -eq 'Tile') { 1 } else { 0 }) -Type "String"
    Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $WallpaperPath -Type "String"

    Add-Type -TypeDefinition @"
        using System.Runtime.InteropServices;
        public class Wallpaper {
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
        }
"@

    $SPI_SETDESKWALLPAPER = 0x0014
    $UpdateIniFile = 0x01
    $SendChangeEvent = 0x02
    $fWinIni = $UpdateIniFile -bor $SendChangeEvent

    [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $WallpaperPath, $fWinIni)
    Write-Host "Wallpaper set to: $WallpaperPath with style: $Style"
}


# Set app and system to use dark theme
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

# Disable Bing Search in Start Menu
Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0

# Hide Recommended section in Start Menu
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_ShowRecommended" -Value 0

# Set Search Box Taskbar Mode to hidden
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0

# Hide Task View button
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0

# Set Taskbar Alignment to left
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0

# Remove Widget button from taskbar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0

# Disable badges on taskbar apps
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarBadges" -Value 0

# Disable flashing of applications in the taskbar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarFlashing" -Value 0

# Disable "Show desktop" button in the far corner of taskbar
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowPeekButton" -Value 0

# Show hidden files
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1

# Show file extensions
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

# Set Initial Keyboard Indicators (NumLock, CapsLock, ScrollLock) to off for current and default users
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0
Set-RegistryValue -Path "HKU\.DEFAULT\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0

# Set keyboard repeat delay (0 = Shortest) and rate (31 = Fastest)
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Type "String"

# Disables mouse acceleration
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value 0

# Disable Sticky Keys
Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value 58

# Disable verbose status messages during startup/shutdown
Set-RegistryValue -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 0

# Disable Window Arrangement
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "WindowArrangementActive" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0

# Disable emoticon display for crash control (Blue Screen of Death)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "DisplayParameters" -Value 0

# Disable Windows Key combinations
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoWinKeys" -Value 1

# Disable Dynamic Lighting feature in Settings
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowDynamicLighting" -Value 0

# Set UAC to never notify
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1

# Set environment to education mode
Set-RegistryValue -Path "HKLM:\Software\Microsoft\PolicyManager\default\Education" -Name "IsEducationEnvironment" -Value 1

# Set WezTerm config path
Set-RegistryValue -Path "HKCU:\Environment" -Name "WEZTERM_CONFIG_FILE" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\modules\wezterm\config\wezterm.lua" -Type "String"

# Set GlazeWM config path
Set-RegistryValue -Path "HKCU:\Environment" -Name "GLAZEWM_CONFIG_PATH" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\programs\glazewm\config.yaml" -Type "String"

# Set lock screen and desktop wallpaper
if (Test-Path $localWallpaperPath) {
    Set-Wallpaper -WallpaperPath $localWallpaperPath -Style "Fill"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "LockScreenImage" -Value $localWallpaperPath -Type "String"
}


Write-Host "Applying UI changes by restarting explorer.exe..."
Stop-Process -Name explorer -Force

Write-Host "Script finished successfully."

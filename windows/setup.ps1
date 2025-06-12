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
            "DWord" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force -ErrorAction Stop }
            "String" { Set-ItemProperty -Path $Path -Name $Name -Value "$Value" -Type String -Force -ErrorAction Stop }
            "Binary" { Set-ItemProperty -Path $Path -Name $Name -Value ([byte[]]$Value) -Type Binary -Force -ErrorAction Stop }
        }
        Write-Host "Set $Path\$Name to $Value ($Type)"
    } catch {
        Write-Error "Failed to set registry value '$Name' at path '$Path'. Error: $_"
    }
}

function Set-ProtectedRegistryValue {
    Param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        $key = $null
        if (-not (Test-Path $Path)) {
            $key = New-Item -Path $Path -Force -PassThru
        } else {
            $key = Get-Item -Path $Path
        }

        $acl = $key.GetAccessControl()
        $originalOwner = $acl.Owner
        $administrators = [System.Security.Principal.NTAccount]"Administrators"
        $acl.SetOwner($administrators)
        $key.SetAccessControl($acl)
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $administrators,
            "FullControl",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        $key.SetAccessControl($acl)
        Set-RegistryValue -Path $Path -Name $Name -Value $Value -Type $Type
        $acl.SetOwner([System.Security.Principal.NTAccount]$originalOwner)
        $key.SetAccessControl($acl)
        Write-Host "Successfully set protected registry value for $Name"
    } catch {
        Write-Error "Failed to set protected registry value '$Name' at path '$Path'. Error: $_"
    }
}

function Set-Wallpaper {
    param(
        [string]$WallpaperPath,
        [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
        [string]$Style = 'Fill'
    )
    if (-not (Test-Path $WallpaperPath)) {
        Write-Error "Wallpaper file not found: $WallpaperPath"; return
    }
    $WallpaperStyle = switch ($Style) {
        'Fill' { 10 }; 'Fit' { 6 }; 'Stretch' { 2 }; 'Tile' { 1 }; 'Center' { 0 }; 'Span' { 22 }
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
    [Wallpaper]::SystemParametersInfo(20, 0, $WallpaperPath, 3)
    Write-Host "Wallpaper set to: $WallpaperPath with style: $Style"
}

Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "HideRecommendedSection" -Value 1

Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
Set-ProtectedRegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarBadges" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarFlashing" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowPeekButton" -Value 0

Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0
try {
    Write-Host "Loading .DEFAULT user hive to modify keyboard settings..."
    reg load HKU\TempDefault "C:\Users\Default\NTUSER.DAT"
    reg add "HKU\TempDefault\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 0 /f
    Write-Host "Successfully set InitialKeyboardIndicators for .DEFAULT user."
} catch {
    Write-Error "Failed to modify .DEFAULT user hive. Error: $_"
} finally {
    reg unload HKU\TempDefault | Out-Null
    Write-Host "Unloaded .DEFAULT user hive."
}
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value 58

Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WindowArrangementActive" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "DisplayParameters" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoWinKeys" -Value 1
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education" -Name "IsEducationEnvironment" -Value 1

Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\Windows\DynamicLighting" -Name "EnableDynamicLighting" -Value 0

Set-RegistryValue -Path "HKCU:\Environment" -Name "WEZTERM_CONFIG_FILE" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\modules\wezterm\config\wezterm.lua" -Type "String"
Set-RegistryValue -Path "HKCU:\Environment" -Name "GLAZEWM_CONFIG_PATH" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\programs\glazewm\config.yaml" -Type "String"

if (Test-Path $localWallpaperPath) {
    Set-Wallpaper -WallpaperPath $localWallpaperPath -Style "Fill"
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device" -Name "LockScreenImage" -Value $localWallpaperPath -Type "String"
}

Write-Host "Applying UI changes by restarting explorer.exe..."
Stop-Process -Name explorer -Force

Write-Host "Script finished successfully. A reboot is recommended for all changes (like lock screen and system policies) to take full effect."

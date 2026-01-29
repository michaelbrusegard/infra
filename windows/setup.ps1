# =============================================================================
# SCRIPT INITIALIZATION AND ADMIN CHECK
# =============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Warning "This script requires administrator privileges. Please re-run as Administrator."
  if ($Host.Name -eq "ConsoleHost") {
    Read-Host "Press Enter to exit"
  }
  Exit
}

# =============================================================================
# WALLPAPER SETUP
# =============================================================================
Write-Host "--- Initializing Wallpaper Setup ---"
$wslWallpaperPath = "\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\nix-config\wallpapers\twilight-peaks.png"
$localWallpaperDir = Join-Path -Path $env:USERPROFILE -ChildPath "Pictures\Wallpapers"
$localWallpaperPath = Join-Path -Path $localWallpaperDir -ChildPath "twilight-peaks.png"

if (Test-Path $wslWallpaperPath) {
  if (-not (Test-Path $localWallpaperDir)) {
    Write-Host "Creating local wallpaper directory at $localWallpaperDir..."
    New-Item -Path $localWallpaperDir -ItemType Directory -Force | Out-Null
  }
  Write-Host "Copying wallpaper from WSL to $localWallpaperPath..."
  Copy-Item -Path $wslWallpaperPath -Destination $localWallpaperPath -Force
} else {
  Write-Warning "Wallpaper source file not found at $wslWallpaperPath. Skipping wallpaper setup."
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================
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
    Write-Host "Set registry: $Path\$Name to $Value ($Type)"
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
    'Fill' { 10 }
    'Fit' { 6 }
    'Stretch' { 2 }
    'Tile' { 1 }
    'Center' { 0 }
    'Span' { 22 }
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
  Write-Host "Desktop wallpaper set to: $WallpaperPath with style: $Style"
}

function Set-LockScreen {
  param([string]$ImagePath)

  if (-not (Test-Path $ImagePath)) {
    Write-Warning "Lock screen image not found at $ImagePath. Skipping."
    return
  }

  $cspPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

  Write-Host "Setting lock screen image using PersonalizationCSP..."
  Set-RegistryValue -Path $cspPath -Name "LockScreenImagePath" -Value $ImagePath -Type "String"
  Set-RegistryValue -Path $cspPath -Name "LockScreenImageUrl" -Value $ImagePath -Type "String"
  Set-RegistryValue -Path $cspPath -Name "LockScreenImageStatus" -Value 1 -Type "DWord"

  Write-Host "Resetting permissions on SystemData cache to apply lock screen..."
  try {
    Start-Process -FilePath "icacls" -ArgumentList '"C:\ProgramData\Microsoft\Windows\SystemData" /reset /t /c /l' -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop
    Write-Host "Successfully reset SystemData permissions."
  } catch {
    Write-Error "Failed to reset SystemData permissions. This may prevent the lock screen from updating. Error: $_"
  }
}

# =============================================================================
# WINGET PACKAGE INSTALLATION
# =============================================================================
Write-Host "`n--- Installing Applications with Winget ---"

$packages = @(
  "Git.Git",
  "uutils.coreutils",
  "Fastfetch-cli.Fastfetch",
  "Microsoft.PowerShell",
  "7zip.7zip",
  "Rufus.Rufus",
  "Rem0o.FanControl",
  "Notepad++.Notepad++",
  "VB-Audio.Voicemeeter.Banana",
  "FocusriteAudioEngineeringLtd.FocusriteControl",
  "Microsoft.PowerToys",
  "glzr-io.glazewm",
  "wez.wezterm",
  "Zen-Team.Zen-Browser",
  "Proton.ProtonMail",
  "Proton.ProtonPass",
  "Proton.ProtonVPN",
  "Proton.ProtonDrive",
  "smartfrigde.Legcord",
  "OBSProject.OBSStudio",
  "RiotGames.Valorant.EU",
  "RiotGames.LeagueOfLegends.EUW",
  "Blitz.Blitz",
  "Valve.Steam",
  "EpicGames.EpicGamesLauncher",
  "GOG.Galaxy",
  "Ubisoft.Connect",
  "Modrinth.ModrinthApp",
  "FTB.App"
)

foreach ($packageId in $packages) {
  Write-Host "Attempting to install $packageId..."
  winget install --id $packageId --silent --accept-source-agreements --accept-package-agreements

  if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully installed $packageId."
  } else {
    Write-Warning "Failed to install $packageId. Exit code: $LASTEXITCODE. You may need to install it manually."
  }
}

# =============================================================================
# POWERSHELL 7 MODULE INSTALLATION
# =============================================================================
Write-Host "`n--- Installing PowerShell 7 Modules ---"
$pwshExePath = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"

if (Test-Path $pwshExePath) {
  Write-Host "PowerShell 7 found. Installing 'pure-pwsh' module for it..."
  try {
    $command = "Install-Module -Name pure-pwsh -Scope AllUsers -Force -ErrorAction Stop"
    Start-Process -FilePath $pwshExePath -ArgumentList "-Command", $command -Wait -NoNewWindow -ErrorAction Stop
    Write-Host "Successfully installed 'pure-pwsh' module for PowerShell 7."
  }
  catch {
    Write-Warning "Failed to install 'pure-pwsh' module for PowerShell 7. Error: $_"
  }
}
else {
  Write-Warning "PowerShell 7 executable not found at '$pwshExePath'. Skipping 'pure-pwsh' module installation."
}

# =============================================================================
# POWERSHELL PROFILE SETUP
# =============================================================================
Write-Host "`n--- Setting up PowerShell 7 Profile ---"

$wslProfilePath = "\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\nix-config\windows\programs\powershell\profile.ps1"
$documentsFolder = [Environment]::GetFolderPath('MyDocuments')
$ps7ProfileDirectory = Join-Path -Path $documentsFolder -ChildPath "PowerShell"
$ps7ProfilePath = Join-Path -Path $ps7ProfileDirectory -ChildPath "profile.ps1"

Write-Host "Target PowerShell 7 profile location: $ps7ProfilePath"

if (-not (Test-Path $wslProfilePath)) {
  Write-Warning "Source profile not found at '$wslProfilePath'. Skipping profile setup."
}
else {
  try {
    if (-not (Test-Path $ps7ProfileDirectory)) {
      Write-Host "Creating PowerShell profile directory: $ps7ProfileDirectory"
      New-Item -Path $ps7ProfileDirectory -ItemType Directory -Force | Out-Null
    }
    if (Test-Path $ps7ProfilePath) {
      Write-Host "Removing existing profile at '$ps7ProfilePath' to create new symlink."
      Remove-Item -Path $ps7ProfilePath -Force
    }
    Write-Host "Creating symbolic link from '$ps7ProfilePath' to '$wslProfilePath'..."
    New-Item -ItemType SymbolicLink -Path $ps7ProfilePath -Value $wslProfilePath -Force -ErrorAction Stop
    Write-Host "Successfully linked PowerShell 7 profile."
  }
  catch {
    Write-Error "Failed to create PowerShell profile symlink. Error: $_"
  }
}

# =============================================================================
# APPLYING REGISTRY MODIFICATIONS
# =============================================================================
Write-Host "`n--- Configuring System Theme ---"
Write-Host "Setting Apps & System theme to Dark Mode."
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

Write-Host "`n--- Configuring Start Menu & Search ---"
Write-Host "Disabling Bing Search in Start Menu."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
Write-Host "Hiding 'Recommended' section in Start Menu."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "HideRecommendedSection" -Value 1

Write-Host "`n--- Configuring Taskbar ---"
Write-Host "Hiding search box from taskbar."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0
Write-Host "Hiding Task View (Timeline) button."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
Write-Host "Aligning taskbar to the left."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
Write-Host "Disabling News and Interests widget."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
Write-Host "Disabling taskbar icon badges."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarBadges" -Value 0
Write-Host "Disabling taskbar icon flashing."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarFlashing" -Value 0
Write-Host "Hiding 'Show Desktop' button."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowPeekButton" -Value 0

Write-Host "`n--- Configuring File Explorer ---"
Write-Host "Showing hidden files, folders, and drives."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
Write-Host "Showing file extensions."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

Write-Host "`n--- Configuring Input Devices (Keyboard & Mouse) ---"
Write-Host "Disabling NumLock on startup for current user."
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0
try {
  Write-Host "Disabling NumLock on startup for the login screen (.DEFAULT user)."
  reg load HKU\TempDefault "C:\Users\Default\NTUSER.DAT"
  reg add "HKU\TempDefault\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 0 /f
  Write-Host "Successfully set InitialKeyboardIndicators for .DEFAULT user."
} catch {
  Write-Error "Failed to modify .DEFAULT user hive. Error: $_"
} finally {
  reg unload HKU\TempDefault | Out-Null
  Write-Host "Unloaded .DEFAULT user hive."
}
Write-Host "Setting keyboard repeat rate to fastest."
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Type "String"
Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Type "String"
Write-Host "Disabling mouse acceleration."
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value 0
Set-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value 0
Write-Host "Disabling Sticky Keys prompt."
Set-RegistryValue -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Value 58

Write-Host "`n--- Configuring System & UI Behavior ---"
Write-Host "Disabling verbose status messages during startup/shutdown."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 0
Write-Host "Disabling Snap Assist features."
Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WindowArrangementActive" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SnapAssist" -Value 0
Write-Host "Disabling parameter display on blue screen."
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "DisplayParameters" -Value 0
Write-Host "Disabling Windows Key shortcuts."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoWinKeys" -Value 1
Write-Host "Configuring UAC to not dim the screen."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
Write-Host "Setting environment to 'Education' to reduce ads/suggestions."
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education" -Name "IsEducationEnvironment" -Value 1

Write-Host "`n--- Configuring Miscellaneous Settings ---"
Write-Host "Disabling Ambient/Dynamic Lighting feature."
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Lighting" -Name "AmbientLightingEnabled" -Value 0

Write-Host "`n--- Setting Environment Variables ---"
Write-Host "Setting WEZTERM_CONFIG_FILE environment variable."
Set-RegistryValue -Path "HKCU:\Environment" -Name "WEZTERM_CONFIG_FILE" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\nix-config\config\wezterm\wezterm.lua" -Type "String"
Write-Host "Setting GLAZEWM_CONFIG_PATH environment variable."
Set-RegistryValue -Path "HKCU:\Environment" -Name "GLAZEWM_CONFIG_PATH" -Value "\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\nix-config\windows\programs\glazewm\config.yaml" -Type "String"

# =============================================================================
# APPLYING VISUAL CHANGES
# =============================================================================
if (Test-Path $localWallpaperPath) {
  Write-Host "`n--- Applying Wallpaper and Lock Screen ---"
  Set-Wallpaper -WallpaperPath $localWallpaperPath -Style "Fill"
  Set-LockScreen -ImagePath $localWallpaperPath
}

Write-Host "`n--- Finalizing Changes ---"
Write-Host "Applying UI changes by restarting explorer.exe..."
Stop-Process -Name explorer -Force

Write-Host "`nScript finished successfully. A reboot is required for all changes to take full effect."

# =============================================================================
# PARAMETERS
# =============================================================================
[CmdletBinding()]
Param(
  [string]$WslDistro = "NixOS",
  [string]$WslUser   = "michaelbrusegard",
  [string]$RepoPath  = "Projects/infra"
)

$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Section {
  Param(
    [string]$Name,
    [scriptblock]$Body
  )
  Write-Host "`n--- $Name ---"
  try {
    & $Body
  } catch {
    Write-Error "Section '$Name' failed: $_"
    $failures.Add($Name)
  }
}

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
# WSL AVAILABILITY GATE
# =============================================================================
# All UNC paths below depend on the WSL distro being reachable. Start it
# eagerly so subsequent \\wsl.localhost\... access doesn't fail silently.
Write-Host "--- Verifying WSL distro '$WslDistro' is reachable ---"
$wslRoot     = "\\wsl.localhost\$WslDistro"
$wslHome     = "$wslRoot\home\$WslUser"
$wslRepoUnc  = Join-Path $wslHome ($RepoPath -replace '/', '\')

& wsl.exe -d $WslDistro -e true 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Error "WSL distro '$WslDistro' is not available. Install/start it and retry."
  exit 1
}
if (-not (Test-Path $wslRepoUnc)) {
  Write-Error "Repo path '$wslRepoUnc' not found in WSL. Aborting."
  exit 1
}
Write-Host "WSL '$WslDistro' OK. Repo: $wslRepoUnc"

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

function Set-Symlink {
  Param(
    [Parameter(Mandatory)][string]$LinkPath,
    [Parameter(Mandatory)][string]$TargetPath
  )
  if (-not (Test-Path $TargetPath)) {
    Write-Warning "Symlink target missing: $TargetPath. Skipping link $LinkPath."
    return
  }
  $parent = Split-Path -Parent $LinkPath
  if (-not (Test-Path $parent)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }
  $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
  if ($existing) {
    if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -contains $TargetPath) {
      Write-Host "Symlink already correct: $LinkPath -> $TargetPath"
      return
    }
    Write-Host "Replacing $LinkPath"
    Remove-Item -LiteralPath $LinkPath -Force -Recurse
  }
  New-Item -ItemType SymbolicLink -Path $LinkPath -Value $TargetPath -Force -ErrorAction Stop | Out-Null
  Write-Host "Linked $LinkPath -> $TargetPath"
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
# WALLPAPER SETUP
# =============================================================================
Invoke-Section "Wallpaper Setup" {
  $wslWallpaperPath  = Join-Path $wslRepoUnc "wallpapers\twilight-peaks.png"
  $script:localWallpaperDir  = Join-Path $env:USERPROFILE "Pictures\Wallpapers"
  $script:localWallpaperPath = Join-Path $localWallpaperDir "twilight-peaks.png"

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
}

# =============================================================================
# WINGET PACKAGE INSTALLATION
# =============================================================================
Invoke-Section "Installing Applications with Winget" {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found. Install App Installer from the Microsoft Store first."
  }

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
    "wez.wezterm",
    "Zen-Team.Zen-Browser",
    "smartfrigde.Legcord",
    "OBSProject.OBSStudio",
    "RiotGames.Valorant.EU",
    "RiotGames.LeagueOfLegends.EUW",
    "Blitz.Blitz",
    "Valve.Steam",
    "EpicGames.EpicGamesLauncher",
    "GOG.Galaxy",
    "Ubisoft.Connect"
  )

  $wingetFailures = @()
  foreach ($packageId in $packages) {
    Write-Host "Attempting to install $packageId..."
    winget install --id $packageId --silent --accept-source-agreements --accept-package-agreements
    # 0 = success, -1978335189 = already installed (no upgrade needed)
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
      Write-Host "OK: $packageId"
    } else {
      Write-Warning "Failed to install $packageId. Exit code: $LASTEXITCODE."
      $wingetFailures += $packageId
    }
  }

  if ($wingetFailures.Count -gt 0) {
    Write-Warning "Winget packages failed: $($wingetFailures -join ', ')"
  }
}

# =============================================================================
# POWERSHELL 7 MODULE INSTALLATION
# =============================================================================
Invoke-Section "Installing PowerShell 7 Modules" {
  $pwshExePath = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"

  if (Test-Path $pwshExePath) {
    Write-Host "PowerShell 7 found. Installing 'pure-pwsh' module for it..."
    $command = "Install-Module -Name pure-pwsh -Scope AllUsers -Force -ErrorAction Stop"
    Start-Process -FilePath $pwshExePath -ArgumentList "-Command", $command -Wait -NoNewWindow -ErrorAction Stop
    Write-Host "Successfully installed 'pure-pwsh' module for PowerShell 7."
  } else {
    Write-Warning "PowerShell 7 executable not found at '$pwshExePath'. Skipping 'pure-pwsh' module installation."
  }
}

# =============================================================================
# CONFIG SYMLINKS (PowerShell profile, FanControl)
# =============================================================================
Invoke-Section "Linking config files from WSL" {
  $documentsFolder = [Environment]::GetFolderPath('MyDocuments')

  # PowerShell 7 profile
  Set-Symlink `
    -LinkPath   (Join-Path $documentsFolder "PowerShell\profile.ps1") `
    -TargetPath (Join-Path $wslRepoUnc "windows\programs\powershell\profile.ps1")

  # FanControl config
  Set-Symlink `
    -LinkPath   (Join-Path $env:APPDATA "FanControl\Configurations\userConfig.json") `
    -TargetPath (Join-Path $wslRepoUnc "windows\programs\fancontrol\userConfig.json")
}

# =============================================================================
# CUSTOM KEYBOARD LAYOUT INSTALL
# =============================================================================
Invoke-Section "Installing custom keyboard layout" {
  $keyboardZip = Join-Path $wslRepoUnc "windows\keyboard.zip"
  if (-not (Test-Path $keyboardZip)) {
    Write-Warning "Keyboard zip not found at $keyboardZip. Skipping."
    return
  }

  $extractDir = Join-Path $env:TEMP "infra-keyboard"
  if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
  Expand-Archive -Path $keyboardZip -DestinationPath $extractDir -Force

  $setupExe = Get-ChildItem -Path $extractDir -Recurse -Filter "setup.exe" | Select-Object -First 1
  if (-not $setupExe) {
    Write-Warning "setup.exe not found inside $keyboardZip. Skipping."
    return
  }

  Write-Host "Launching $($setupExe.FullName) (UAC prompt will appear)..."
  Start-Process -FilePath $setupExe.FullName -Wait
  Write-Host "Keyboard layout installer finished. Add it via Settings -> Time & Language -> Language."
}

# =============================================================================
# APPLYING REGISTRY MODIFICATIONS
# =============================================================================
Invoke-Section "Configuring System Theme" {
  Write-Host "Setting Apps & System theme to Dark Mode."
  Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
  Set-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
}

Invoke-Section "Configuring Start Menu & Search" {
  Write-Host "Disabling Bing Search in Start Menu."
  Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
  Write-Host "Hiding 'Recommended' section in Start Menu."
  Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "HideRecommendedSection" -Value 1
}

Invoke-Section "Configuring Taskbar" {
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
}

Invoke-Section "Configuring File Explorer" {
  Write-Host "Showing hidden files, folders, and drives."
  Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
  Write-Host "Showing file extensions."
  Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
}

Invoke-Section "Configuring Input Devices (Keyboard & Mouse)" {
  Write-Host "Disabling NumLock on startup for current user."
  Set-RegistryValue -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 0

  Write-Host "Disabling NumLock on startup for the login screen (.DEFAULT user)."
  $hiveLoaded = $false
  try {
    reg load HKU\TempDefault "C:\Users\Default\NTUSER.DAT" | Out-Null
    if ($LASTEXITCODE -eq 0) {
      $hiveLoaded = $true
      reg add "HKU\TempDefault\Control Panel\Keyboard" /v InitialKeyboardIndicators /t REG_SZ /d 0 /f | Out-Null
      Write-Host "Successfully set InitialKeyboardIndicators for .DEFAULT user."
    } else {
      Write-Warning "Could not load Default user hive (exit $LASTEXITCODE). Skipping."
    }
  } catch {
    Write-Error "Failed to modify .DEFAULT user hive. Error: $_"
  } finally {
    if ($hiveLoaded) {
      [gc]::Collect()
      reg unload HKU\TempDefault | Out-Null
      Write-Host "Unloaded .DEFAULT user hive."
    }
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
}

Invoke-Section "Configuring System & UI Behavior" {
  Write-Host "Disabling verbose status messages during startup/shutdown."
  Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Value 0
  Write-Host "Disabling parameter display on blue screen."
  Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "DisplayParameters" -Value 0
  Write-Host "Configuring UAC to not dim the screen."
  Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0
  Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
  Write-Host "Setting environment to 'Education' to reduce ads/suggestions."
  Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education" -Name "IsEducationEnvironment" -Value 1
}

Invoke-Section "Configuring Miscellaneous Settings" {
  Write-Host "Disabling Ambient/Dynamic Lighting feature."
  Set-RegistryValue -Path "HKCU:\Software\Microsoft\Lighting" -Name "AmbientLightingEnabled" -Value 0
}

# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================
Invoke-Section "Setting Environment Variables" {
  $weztermConfigPath = Join-Path $wslHome ".config\wezterm\wezterm.lua"
  [Environment]::SetEnvironmentVariable("WEZTERM_CONFIG_FILE", $weztermConfigPath, "User")
  Write-Host "Set WEZTERM_CONFIG_FILE to $weztermConfigPath"
}

# =============================================================================
# APPLYING VISUAL CHANGES
# =============================================================================
Invoke-Section "Applying Wallpaper and Lock Screen" {
  if (Test-Path $localWallpaperPath) {
    Set-Wallpaper -WallpaperPath $localWallpaperPath -Style "Fill"
    Set-LockScreen -ImagePath $localWallpaperPath
  } else {
    Write-Warning "Local wallpaper not present at $localWallpaperPath. Skipping."
  }
}

# =============================================================================
# FINALIZE
# =============================================================================
Invoke-Section "Finalizing Changes" {
  Write-Host "Applying UI changes by restarting explorer.exe..."
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
    Start-Process explorer
  }
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
if ($failures.Count -eq 0) {
  Write-Host "Script finished successfully. A reboot is recommended for all changes to take full effect."
} else {
  Write-Warning "Script finished with $($failures.Count) failed section(s):"
  $failures | ForEach-Object { Write-Warning "  - $_" }
  Write-Warning "Review the errors above and re-run after addressing them."
}

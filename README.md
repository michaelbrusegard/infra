# Dotfiles

This is primarily a guide for myself on how to setup my own systems, feel free to copy any of the dotfiles, but do not expect a direct copy of everything to work for you.

Make sure to follow the guide for each system step by step and to move over an SSH key for GitHub to get started with cloning the repository.
Then, clone the repository into `~/Developer/dotfiles` using SSH:

```zsh
git clone git@github.com:michaelbrusegard/dotfiles.git ~/Developer/dotfiles
```

> [!NOTE]
> I also maintain a private repository with soft and hard secrets that is added into the repository as a Nix flake. Directly copying the dotfiles will therefore most likely fail since it will fail to fetch the private repository.

Hard secrets are encrypted further inside the private repository using sops. To include them in the build, add the age keys to `~/.config/sops/age/keys.txt` and then do a rebuild.

## Reference links

### Package Repositories

- [Nixpkgs](https://search.nixos.org/packages)
- [Homebrew](https://brew.sh/)
- [WinGet](https://winget.ragerworks.com/)

### Nix Options

- [nixos](https://mynixos.com/nixpkgs/options)
- [nix-darwin](https://mynixos.com/nix-darwin/options)
- [home-manager](https://mynixos.com/home-manager/options)

## Desktop (NixOS)

Create an installer by downloading the graphical ISO image from [here](https://nixos.org/download/#nixos-iso) and flashing it to a USB drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX` with the path to your USB drive.

### Screenshot

![Screenshot 2025-04-26 at 15 07 56](https://github.com/user-attachments/assets/cd56268b-93b1-4bfd-9c1f-2a999428dd6e)

### Initial build

After the installation we need a few things to get started to install the flake configuration:

- Add `git` to system packages in `/etc/nixos/configuration.nix` and rebuild the system `sudo nixos-rebuild switch`.
- Add both the SSH key and the age key to the system, so that we can clone the repository and decrypt secrets.
- Verify that the dotfiles configuration has the same hardware configuration as the `/etc/nixos/hardware-configuration.nix`. Specifically, device file paths and partition UUIDs.
- Create initial secure keys `nix shell nixpkgs#sbctl --command sudo sbctl create-keys`. For the rest of the secure boot setup read [here](https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md). In short, reboot and clear the secure boot keys in the UEFI settings, then enroll the keys using `sbctl enroll-keys --microsoft` and reboot the system.

Then we can install the flake configuration by running the following command:

```sh
sudo nixos-rebuild switch --flake $HOME/Developer/dotfiles#desktop
```

Afterwards delete the old NixOS configuration files:

```sh
sudo rm -rf /etc/nixos
```

And reboot the system:

```sh
sudo reboot now
```

## Darwin systems (Nix-darwin)

First install macOS normally by following the default installation guide on the mac. To access the installer hold the power button during boot to access recovery options. Then go through all the sections below for the initial setup.

### Screenshot

![Screenshot 2025-05-02 at 15 03 38](https://github.com/user-attachments/assets/381c8dce-f0d0-4a91-b38f-544c30a3209a)

### Disabling SIP

System Integrity Protection (SIP) needs to be partially disabled for the [yabai](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) tiling window manager to work correctly.

1. Turn off the mac, then press and hold the power button until "Loading startup options" appears.
   Click Options, then click Continue.

2. In the menu bar, choose `Utilities`, then `Terminal`

3. Run this:

```sh
csrutil enable --without fs --without debug --without nvram
```

After rebooting run this:

```sh
sudo nvram boot-args=-arm64e_preview_abi
```

Then reboot again.

### Command line tools

Install Xcode command line tools:

```sh
xcode-select --install
```

### Install Rosetta

```sh
softwareupdate --install-rosetta --agree-to-license
```

### Install Nix

Run the following command to install Nix:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install
```

When prompted to install `Determinate Nix`, explicitly say `no`.

### Initial build

Build the system the first time using the following command:

```sh
nix run nix-darwin -- switch --flake $HOME/Developer/dotfiles
```

Later rebuilds can use the `rebuild` alias.

### Keyboard daemon for kanata

Download the [Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/main/dist) manually and install the package. Afterwards make sure it is enabled in System Settings, General -> Login Items & Extensions -> Driver Extensions (At the bottom).

Also make sure that `/run/current-system/sw/bin/kanata` is added as an allowed application under Security & Privacy -> Input Monitoring. If `kanata` is already added, remove it and try again.

Lastly, go to Keyboard -> Keyboard Shortcuts... -> Modifier Keys, and make sure the Karabiner DriverKit VirtualHIDDevice is selected as the keyboard.

The nix configuration should handle the rest, for any problems check out [this discussion](https://github.com/jtroo/kanata/discussions/1537) in the kanata repository.

## Windows

To create the installation ISO for Windows, we use Chris Titus Tech's Windows Utility to create a clean telemetry-free ISO that does not require a Microsoft account (This has to be run on a Windows machine). The commands require administrator privileges, so make sure to run PowerShell as administrator.

First, enable execution of scripts in PowerShell:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then load the tool:

```sh
irm "https://christitus.com/win" | iex
```

In the tool we can download an ISO image from Microsoft and then modify it to remove telemetry and other unwanted features. When we have the MicroWin ISO we can flash a USB drive using Rufus.

> [!INFO]
> The current desktop setup uses the AMD RAID driver to run the two NVMe drives in RAID 0. This is not supported by the Windows installer, so we need to add the driver manually. It can be installed from the Motherboard's website. A guide for adding the driver can be found [here](https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/user-guides/56268_1_11.pdf). It can be found [here](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/). Here

After installation go to Windows Update and run it to make sure the system is updated.

Also make sure to install updated drivers for the system, the download pages for the current system can be found below:

- [Chipset and Motherboard](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/)
- [Processor](https://www.amd.com/en/support/downloads/drivers.html/processors/ryzen/ryzen-5000-series/amd-ryzen-9-5900x.html)
- [Graphics](https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-rx/radeon-rx-6000-series/amd-radeon-rx-6800-xt.html)

### Screenshot

### NixOS WSL

First we need to build the NixOS WSL tarball. This can be done by running the following command in the dotfiles directory on a nix machine:

```sh
sudo nix run .#nixosConfigurations.wsl.config.system.build.tarballBuilder
```

Put this on a flash drive and copy it to the Windows machine.

Then start by installing Windows Subsystem for Linux (WSL) on Windows:

```sh
wsl --install --no-distribution
```

Then reboot the computer and install the NixOS WSL tarball by running the following command (You have to move the tarball to the current directory first from the flash drive):

```sh
wsl --install --from-file nixos.wsl
```

To enter the WSL environment, run:

```sh
wsl
```

Now clone the dotfiles repository, add the age keys and rebuild.

### Installing packages

We install windows packages using WinGet from the dotfiles repository in WSL:

```sh
winget import -i \\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\packages.json
```

### Applying system preferences

First rerun the WinUtil tool:

```sh
irm "https://christitus.com/win" | iex
```

In the Tweaks tab, enable the Standard tweaks plus the following:

- Disable Recall
- Disable Background Apps
- Disable Microsoft Copilot
- Disable Intel MM
- Disable Notification Tray/Calendar
- Disable Windows Plaform Binary Table
- Set Display for Performance
- Set Classic Right-Click Menu
- Set Time to UTC
- Remove Microsoft Edge
- Remove Home and Gallery from explorer
- Remove OneDrive

Then set the DNS to Cloudflare.

Under Performance Plan click "Add and Activate Ultimate Performance Profile".

In the Updates tab select "Security Settings" to prevent Windows Updates from automatically installing updates at the worst times.

Apply custom preferences by running the `setup.ps1` script:

```sh
powershell -ExecutionPolicy Bypass -File \\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\setup.ps1
```

### Keyboard

The custom keyboard layout is set up like the default US layout, but with mac like behaviour for special characters when holding AltGr (This helps with typing Norwegian characters like æøå when using the US layout). It is configured with [MSKLC](https://www.microsoft.com/en-us/download/details.aspx?id=102134) and the configuration can be imported into the app to be edited via `keyboard.klc`.

To apply the custom keyboard layout copy the `keyboard.zip` file from WSL:

```sh
cp \\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\keyboard.zip C:\Users\michaelbrusegard\Downloads\
```

Then extract the file and open the keyboard directory. From there run the `setup.exe` file to install the custom keyboard layout. Make sure to set it as the default keyboard layout in the Windows settings.

### Run GlazeWM on startup

Create a shortcut for the executable by right-clicking on the GlazeWM executable -> Create shortcut. Put the shortcut in your startup folder, which you can get to by entering shell:startup in the top bar in File Explorer.

### Fonts

To make the SFMono Nerd Font work in WezTerm, each `.otf` font file needs to be manually downloaded and installed from [here](https://github.com/epk/SF-Mono-Nerd-Font/releases/tag/v18.0d1e1.0).

### BitLocker

Lastly remember to enable BitLocker on the system drive to encrypt the system drive. This is done by going to Settings -> Privacy & Security -> Device Encryption and enabling it. If you have a TPM chip, it will be used to store the encryption keys securely.

## Leggero (Raspberry Pi NixOS Mini Apartment Server)

Build the SD image on a machine with `nix` using the following command:

```sh
nix build .#
```

The resulting image can be found in `result/sd-image/`. It is a compressed Zstandard archive that can be flashed to an SD card.

## Flashing the SD Card

We need to plug in the SD card and find out what the device path is for the SD card.

On linux:

```sh
lsblk
```

On darwin:

```sh
diskutil list
```

On linux it is usually `/dev/sdX` where `X` is a letter, for example `/dev/sdb`. On darwon it is usually `/dev/diskX` where `X` is a number for example `/dev/disk6`.

To flash the image to the SD card you can use the following command, make sure to replace `/dev/XXX` with the correct device path for your SD card:

```sh
zstd -dc result/sd-image/*.zst | sudo dd of=/dev/XXX bs=4M status=progress oflag=sync

## Espresso (Ubuntu Home Server)

### Installing packages

```sh
sh ~/dotfiles/espresso/scripts/apt.sh
```

### Setting up symlinks

```sh
cd ~/dotfiles/espresso && stow --adopt -t ~ home && sudo stow --adopt -t /etc etc && stow --adopt -t /data data && git restore .
```

### Setup login items

```sh
sh ~/dotfiles/espresso/scripts/login.sh
```

## Inspiration…

- LGUG2Z'z [nix-wsl-starter](https://github.com/LGUG2Z/nixos-wsl-starter)
- Andrey0189's [Nix Hyprland configuration](https://github.com/Andrey0189/nixos-config-reborn/tree/master/home-manager/modules/hyprland)
- Notusknot's [nix-dotfiles](https://github.com/notusknot/dotfiles-nix)
- Mathias Bynens and his [macOS defaults](https://github.com/mathiasbynens/dotfiles/blob/main/.macos)
- Dries Vints and his [SSH script](https://github.com/driesvints/dotfiles/blob/main/ssh.sh)
- Antione Martin and his [GPG script](https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh)
- Elliot's fast and beautiful [.zshrc prompt](https://github.com/dreamsofautonomy/zensh/blob/main/.zshrc)
- [Michael Bao's dotfiles](https://github.com/tcmmichaelb139/.dotfiles)
- [Josean Martinez's dotfiles](https://github.com/josean-dev/dev-environment-files)
- [TheBlueRuby's awesome Arch Linux setup](https://github.com/TheBlueRuby/dotfiles-arch)

# nix-config

This is primarily a guide for myself on how to setup my own systems, feel free
to copy anything, but do not expect a direct copy of everything to
work for you.

Make sure to follow the guide for each system step by step and to move over
an SSH key for GitHub to get started with cloning the repository.
Then, clone the repository into `~/Developer/dotfiles` using SSH:

```zsh
git clone git@github.com:michaelbrusegard/dotfiles.git ~/Developer/dotfiles
```

> [!NOTE]
> I also maintain a private repository with soft and hard secrets that is added
> into the repository as a Nix flake.
> Directly copying the dotfiles will therefore
> most likely fail since it will fail to fetch the private repository.

Hard secrets are encrypted further inside the private repository using sops.
To include them in the build, add the age keys to `~/.config/sops/age/keys.txt`
and then do a rebuild.

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

Create an installer by downloading the graphical ISO image from
[NixOS download page](https://nixos.org/download/#nixos-iso) and flashing it to
a USB drive
using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

### Screenshot (Desktop)

![Screenshot 2025-04-26 at 15 07 56](https://github.com/user-attachments/assets/cd56268b-93b1-4bfd-9c1f-2a999428dd6e)

### Initial Build (Desktop)

After the installation we need a few things to get started to install the
flake configuration:

- Add `git` to system packages in `/etc/nixos/configuration.nix` and rebuild
  the system `sudo nixos-rebuild switch`.
- Add both the SSH key and the age key to the system, so that we can clone
  the repository and decrypt secrets.
- Verify that the dotfiles configuration has the same hardware configuration
  as the `/etc/nixos/hardware-configuration.nix`. Specifically, device file
  paths and partition UUIDs.
- Create initial secure keys `nix shell nixpkgs#sbctl --command sudo sbctl
  create-keys`. For the rest of the secure boot setup read
  [lanzaboote docs](https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md).
  In short, reboot and clear the secure boot keys in the UEFI settings, then
  enroll the keys using `sbctl enroll-keys --microsoft` and reboot the system.

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

First install macOS normally by following the default installation guide on
the mac. To access the installer hold the power button during boot to access
recovery options. Then go through all the sections below for the initial setup.

### Screenshot (Darwin)

![Screenshot 2025-05-02 at 15 03 38](https://github.com/user-attachments/assets/381c8dce-f0d0-4a91-b38f-544c30a3209a)

### Disabling SIP

System Integrity Protection (SIP) needs to be partially disabled for the
[yabai](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
tiling window manager to work correctly.

1. Turn off the mac, then press and hold the power button until "Loading
   startup options" appears.
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

Accept the license agreement:

```sh
sudo xcodebuild -license accept
```

### Install Rosetta

```sh
softwareupdate --install-rosetta --agree-to-license
```

### Install Nix

Run the following command to install Nix:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | \
  sh -s -- install
```

When prompted to install `Determinate Nix`, explicitly say `no`.

### Initial Build (Darwin)

Build the system the first time using the following command:

```sh
nix run nix-darwin -- switch --flake $HOME/Developer/dotfiles
```

Later rebuilds can use the `rebuild` alias.

### Keyboard daemon for kanata

Download the
[Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/tree/main/dist)
manually and install the package. Afterwards make sure it is enabled in System
Settings, General -> Login Items & Extensions -> Driver Extensions (At the
bottom).

Also make sure that `/run/current-system/sw/bin/kanata` is added as an
allowed application under Privacy & Security -> Input Monitoring. If `kanata`
is already added, remove it and try again. This may have to be redone if
Kanata is updated since the Nix Store path would change.

Lastly, go to Keyboard -> Keyboard Shortcuts... -> Modifier Keys, and make
sure the Karabiner DriverKit VirtualHIDDevice is selected as the keyboard.

The nix configuration should handle the rest, for any problems check out
[this discussion](https://github.com/jtroo/kanata/discussions/1537) in the
kanata repository.

## Windows

To create the installation ISO for Windows, we use Chris Titus Tech's Windows
Utility to create a clean telemetry-free ISO that does not require a Microsoft
account (This has to be run on a Windows machine). The commands require
administrator privileges, so make sure to run PowerShell as administrator.

First, enable execution of scripts in PowerShell:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then load the tool:

```sh
irm "https://christitus.com/win" | iex
```

In the tool we can download an ISO image from Microsoft and then modify it
to remove telemetry and other unwanted features. When we have the MicroWin
ISO we can flash a USB drive using Rufus.

> [!INFO]
> The current desktop setup uses the AMD RAID driver to run the two NVMe
> drives in RAID 0. This is not supported by the Windows installer, so we need
> to add the driver manually. It can be installed from the Motherboard's
> website. A guide for adding the driver can be found
> [AMD RAID guide](
> https://www.amd.com/content/dam/amd/en/documents/processor-tech-docs/user-guides/56268_1_11.pdf
> ).
> It can be found
> [ASUS motherboard downloads](
> https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/
> ).
> Here

After installation go to Windows Update and run it to make sure the
system is updated.

Also make sure to install updated drivers for the system, the download
pages for the current system can be found below:

- [Chipset and Motherboard](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/)
- [Processor and Graphics](https://www.amd.com/en/support/download/drivers.html)

### Screenshot (Windows)

![Screenshot 2025-06-14 at 19 55 23](https://github.com/user-attachments/assets/c56e99a1-d473-4817-b2ee-eaad579ac415)

### NixOS WSL

First we need to build the NixOS WSL tarball. This can be done by running
the following command in the dotfiles directory on a nix machine:

```sh
sudo nix run .#nixosConfigurations.wsl.config.system.build.tarballBuilder
```

Put this on a flash drive and copy it to the Windows machine.

Then start by installing Windows Subsystem for Linux (WSL) on Windows:

```sh
wsl --install --no-distribution
```

Then reboot the computer and install the NixOS WSL tarball by running the
following command (You have to move the tarball to the current directory
first from the flash drive):

```sh
wsl --install --from-file nixos.wsl
```

To enter the WSL environment, run:

```sh
wsl
```

Now clone the dotfiles repository, add the age keys and rebuild.

### Applying system preferences and installing packages

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

In the Updates tab select "Security Settings" to prevent Windows Updates
from automatically installing updates at the worst times.

Then run the `setup.ps1` script to install packages and apply registry tweaks:

```sh
powershell -ExecutionPolicy Bypass -File \
  \\wsl.localhost\NixOS\home\michaelbrusegard\Developer\dotfiles\windows\setup.ps1
```

### Keyboard

The custom keyboard layout is set up like the default US layout, but with
mac like behaviour for special characters when holding AltGr (This helps with
typing Norwegian characters like æøå when using the US layout). It is
configured with [MSKLC](https://www.microsoft.com/en-us/download/details.aspx?id=102134)
and the configuration can be imported into the app to be edited via
`keyboard.klc`.

To apply the custom keyboard layout copy the `keyboard.zip` file from WSL:

```sh
SRC=\\wsl$\\NixOS\\home\\michaelbrusegard\\Developer\\dotfiles\\windows\\keyboard.zip
cp $SRC C:\Users\michaelbrusegard\Downloads
```

The resulting image can be found in `result/sd-image/`. It is a compressed
Zstandard archive that can be flashed to an SD card.

### Flashing the SD Card (Leggero)

We need to plug in the SD card and find out what the device path is for
the SD card.

On linux:

```sh
lsblk
```

On Darwin:

```sh
diskutil list
```

On Linux it is usually `/dev/sdX` where `X` is a letter, for example
`/dev/sdb`. On Darwin it is usually `/dev/diskX` where `X` is a number for
example `/dev/disk6`.

To flash the image to the SD card you can use the following command, make
sure to replace `/dev/XXX` with the correct device path for your SD card:

```sh
zstd -dc result/sd-image/*.zst | sudo dd of=/dev/XXX bs=4M status=progress oflag=sync
```

## Macchiato (NixOS Raspberry Pi Family Home Server)

Build the SD image on a machine with `nix` using the following command:

```sh
nix build .#Macchiato
```

The resulting image can be found in `result/sd-image/`. It is a compressed
Zstandard archive that can be flashed to an SD card.

### Flashing the SD Card (Macchiato)

We need to plug in the SD card and find out what the device path is for
the SD card.

On Linux:

```sh
lsblk
```

On Darwin:

```sh
diskutil list
```

On Linux it is usually `/dev/sdX` where `X` is a letter, for example
`/dev/sdb`. On Darwin it is usually `/dev/diskX` where `X` is a number for
example `/dev/disk6`.

To flash the image to the SD card you can use the following command, make
sure to replace `/dev/XXX` with the correct device path for your SD card:

```sh
zstd -dc result/sd-image/*.zst | sudo dd of=/dev/XXX bs=4M status=progress oflag=sync
```

## Espresso (NixOS K3s Cluster)

The Espresso setup consists of HA k3s nodes (espresso1, espresso2, espresso3)
for running containerized homelab and business services like websites, media
hosting and automation.

### Prerequisites

Start with obtaining MAC addresses for each node by enabling PXE (Preboot
Execution Environment) and writing down the MAC address. Then disable PXE
again and assign a static IP to each node from the router.

### Bootstrap with NixOS Anywhere

First, build the appropriate bootstrap ISO:

```sh
nix build .#bootstrapIsoX86
```

Flash the resulting ISO (`result/iso/*.iso`) to a USB drive:

```sh
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot each node from the USB drive. Once booted, the node will have SSH
enabled with your key.

Then, for each node, run:

```sh
nixos-anywhere --flake ~/Developer/dotfiles#Espresso1 \
  -i ~/.config/sops-nix/secrets/ssh/bootstrap/private-key \
  root@node-ip
```

Replace `Espresso1` with `Espresso2`/`Espresso3` and the correct IP.

### Post-Bootstrap

- Copy sops keys to each node (e.g., via SSH or USB)

### Cluster Management

- Access via `kubectl` after connecting to any node
- Drain nodes for maintenance: `kubectl drain espresso1`
- Uncordon after: `kubectl uncordon espresso1`

## Inspiration…

- LGUG2Z'z [nix-wsl-starter](https://github.com/LGUG2Z/nixos-wsl-starter)
- Andrey0189's [Nix Hyprland configuration](https://github.com/Andrey0189/nixos-config-reborn/tree/master/home-manager/modules/hyprland)
- Notusknot's [nix-dotfiles](https://github.com/notusknot/dotfiles-nix)
- Mathias Bynens and his [macOS defaults](https://github.com/mathiasbynens/dotfiles/blob/main/.macos)
- Dries Vints and his [SSH script](https://github.com/driesvints/dotfiles/blob/main/ssh.sh)
- Antione Martin and his [GPG script](https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh)
- Elliot's fast and beautiful [.zshrc prompt](https://github.com/dreamsofautonomy/zensh/blob/main/.zshrc)
- Michael Bao's [dotfiles](https://github.com/tcmmichaelb139/.dotfiles)
- Josean Martinez's [dev environment files](https://github.com/josean-dev/dev-environment-files)
- TheBlueRuby's [awesome Arch Linux setup](https://github.com/TheBlueRuby/dotfiles-arch)

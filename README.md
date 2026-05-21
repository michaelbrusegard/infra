# infra

This is primarily a guide for myself on how to setup my own systems, feel free
to copy anything, but do not expect a direct copy of everything to
work for you.

Note to self: Make sure to follow the guide for each system step by step.

> [!NOTE]
> I also maintain a private repository with a Nix flake containing soft
> and hard secrets. Directly copying the configuration will therefore fail
> since it will fail to fetch the private repository. The private flake uses
> Age keys to further encrypt the most critical secrets. To include them in
> the build, add the age keys to `~/.config/sops/age/keys.txt`

## Lungo (Nix-darwin Laptop)

First install macOS normally by following the default installation on
the mac. To access the installer hold the power button during boot to access
recovery options. Then go through all the sections below for the initial setup.

### Screenshot (Lungo)

![Screenshot 2025-05-02 at 15 03 38](https://github.com/user-attachments/assets/381c8dce-f0d0-4a91-b38f-544c30a3209a)

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
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

Then run these commmands to move away conflicting nix configuration left by the installer, and clean up the standalone lix launch daemon to prevent boot conflicts:

```sh
sudo mv /etc/nix/nix.custom.conf{,.before-nix-darwin}
sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
sudo launchctl bootout system /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist || true
sudo rm -f /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist
```

### Clone infrastructure configuration (Lungo)

Add the GitHub SSH private key:

```sh
ssh-add ./private-key
```

Then clone the infrastructure configuration:

```sh
git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra
```

### Initial Build (Lungo)

Put the user secrets Age key to `~/.config/sops/age/keys.txt`.
Build the system the first time using the following command:

```sh
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake $HOME/Projects/infra#lungo
```

Later rebuilds can use the `nrs` alias.

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

## Ristretto (NixOS/Windows Desktop)

Create an installer by downloading the minimal ISO image from
[NixOS download page](https://nixos.org/download/#nixos-iso) and flashing it to
an USB drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

### Screenshot (Ristretto)

![Screenshot 2025-04-26 at 15 07 56](https://github.com/user-attachments/assets/cd56268b-93b1-4bfd-9c1f-2a999428dd6e)

### Install NixOS with nixos-anywhere (Using Minimal NixOS Installer)

Plug in the installer USB and boot to it, make sure secure boot keys are cleared or set to setup mode.
Set a temporary password using the `passwd` command for SSH access.
You can run `ip a` to find the IP address.

1. **Prepare Local Files**:
   - Create LUKS passphrase file: `./secret.key`.
   - Get host SSH key: `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`

2. **Run Install**:

   ```sh
   nixos-anywhere --extra-files ./keys --flake .#ristretto --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
   ```

3. **Post-Install**:
   - Setup TPM auto unlock for both LUKS partitions (run `lsblk` to identify which NVMe holds which container — `disk1` has ESP + LUKS, `disk2` has only LUKS):

     ```sh
     sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme1n1p2
     sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p1
     ```

   - Add user Age key to `~/.config/sops/age/keys.txt`).
   - Clone the infrastructure configuration using the GitHub SSH private key: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra`.
   - Rebuild the configuration: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' nh os switch`.

### Create Windows installer

To create the installation ISO for Windows, we use Chris Titus Tech's Windows
Utility to create a clean telemetry-free ISO that does not require a Microsoft
account (This has to be run on a Windows machine or in a VM). The commands require
administrator privileges, so make sure to run PowerShell as administrator.

First, enable execution of scripts in PowerShell:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then load the tool:

```sh
irm "https://christitus.com/win" | iex
```

In the tool we can download the newest Windows ISO image from Microsoft.
Then choose the username and password.
Append the tweaks settings from `windows/winutil.json` and start the process.

When we have the MicroWin
ISO we can flash an USB drive using Rufus.

> [!INFO]
> The current setup also requires the AMD RAID driver to run the two NVMe
> drives in RAID 0. This is not supported by the Windows installer, so we need
> to add the drivers manually. They can be downloaded from here
> [ASUS motherboard downloads](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/).

Create a `drivers` directory on the installer USB and add the rcbottom.inf,
rcraid.inf and rccfg.inf. They should be loaded in that order during the installation.

After installation has finished go to Windows Update and run it to make sure the
system is updated.

Also make sure to install updated drivers for the system, the download
pages for the current system can be found below:

- [Chipset and Motherboard](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/)
- [Processor and Graphics](https://www.amd.com/en/support/download/drivers.html)

### Screenshot (Windows)

![Screenshot 2025-06-14 at 19 55 23](https://github.com/user-attachments/assets/c56e99a1-d473-4817-b2ee-eaad579ac415)

### NixOS WSL

First we need to build the NixOS WSL tarball. This can be done by running
the following command on a nix machine:

```sh
sudo nix run .#nixosConfigurations.ristretto-wsl.config.system.build.tarballBuilder
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

Now clone the infra repository, add the age keys and rebuild.

### Applying system preferences and installing packages

First rerun the WinUtil tool:

```sh
irm "https://christitus.com/win" | iex
```

Under Performance Plan click "Add and Activate Ultimate Performance Profile".

In the Updates tab select "Security Settings" to prevent Windows Updates
from automatically installing updates at the worst times.

Then run the `setup.ps1` script to install packages and apply registry tweaks:

```sh
powershell -ExecutionPolicy Bypass -File \
  \\wsl.localhost\NixOS\home\michaelbrusegard\Projects\infra\windows\setup.ps1
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
SRC=\\wsl$\\NixOS\\home\\michaelbrusegard\\Projects\\infra\\windows\\keyboard.zip
cp $SRC C:\Users\michaelbrusegard\Downloads
```

## Macchiato (NixOS Router)

Create a minimal installer USB by downloading from [here](https://nixos.org/download/#nixos-iso)
and flashing it to the drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

### Prepare the machine

Plug in the USB and boot to it, make sure secure boot keys are cleared or set to setup mode.
Set a temporary password using the `passwd` command for SSH access.
Run `ip a` to find the IP address on the machine.
Alternatively connect it directy to a Mac with "Internet Sharing" enabled.

### Install with NixOS Anywhere

Copy the LUKS passphrase into this relative file: `./secret.key`.
Do the same with the host SSH key: `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`
Run the following installation command, if prompted for a password, it is the temporary password created when preparing the machine.

```sh
nixos-anywhere --extra-files ./keys --flake .#macchiato --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
```

### Post install

Add the admin Age key to `~/.config/sops/age/keys.txt`) to be able to decrypt user secrets.
**Important:** Setup TPM auto unlock: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/sda2`.

## Espresso (NixOS K3S Cluster)

The Espresso setup consists of the nodes espresso-0, espresso-1 and espresso-2
in a k3s cluster. So the following bootstrap has to be done for each of the nodes.
It is important to do espresso-0 first so the cluster is bootstrapped.

First create a minimal installer USB by downloading from [here](https://nixos.org/download/#nixos-iso)
and flashing it to the drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

### Prepare the node

Plug in the USB and boot to it, make sure secure boot keys are cleared or set to setup mode.
Set a temporary password using the `passwd` command for SSH access.
Run `ip a` to find the IP address on the machine.
Alternatively connect it directy to a Mac with "Internet Sharing" enabled.

### Install with NixOS Anywhere

Copy the LUKS passphrase into this relative file: `./secret.key`.
Do the same with the host SSH key: `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`
Run the following installation command, if prompted for a password, it is the temporary password created when preparing the machine.

```sh
nixos-anywhere --extra-files ./keys --flake .#espresso-NODE --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
```

### Post install

Add the admin Age key to `~/.config/sops/age/keys.txt`) to be able to decrypt user secrets. Then
rebuild the configuration using colmena.

Setup TPM auto unlock for all the applicable disks (run `lsblk` to see the disks):

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
# These will only be applicable for espresso-1 and espresso-2:
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/sda1
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/sdb1
```

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

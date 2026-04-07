# nix-config

This is primarily a guide for myself on how to setup my own systems, feel free
to copy anything, but do not expect a direct copy of everything to
work for you.

Note to self: Make sure to follow the guide for each system step by step.

> [!NOTE]
> I also maintain a private repository with a nix flake containing soft
> and hard secrets. Directly copying the configuration will therefore fail
> since it will fail to fetch the private repository. The private flake uses
> Age keys to further encrypt the most critical secrets. To include them in
> the build, add the age keys to `~/.config/sops/age/keys.txt`

## Reference links

### Package Repositories

- [Nixpkgs](https://search.nixos.org/packages)
- [Homebrew](https://brew.sh/)
- [WinGet](https://winget.ragerworks.com/)

### Nix Options

- [nixos](https://mynixos.com/nixpkgs/options)
- [nix-darwin](https://mynixos.com/nix-darwin/options)
- [home-manager](https://mynixos.com/home-manager/options)

## Lungo (Nix-darwin Laptop)

First install macOS normally by following the default installation on
the mac. To access the installer hold the power button during boot to access
recovery options. Then go through all the sections below for the initial setup.

### Screenshot (Lungo)

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

### Clone nix configuration (Lungo)

Move over the GitHub SSH private key and make sure SSH works.
Move the user secrets Age key to `~/.config/sops/age/keys.txt`.
Then clone the nix configuration:

```sh
git clone git@github.com:michaelbrusegard/nix-config.git ~/Projects/nix-config
```

### Initial Build (Lungo)

Build the system the first time using the following command:

```sh
nix run nix-darwin -- switch --flake $HOME/Projects/nix-config#lungo
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

### Install NicOS with nixos-anywhere (Using Minimal NixOS Installer)

Plug in the installer USB and set a temporary password using the `passwd` command for SSH access.
You can run `ip a` to find the IP address.

1. **Prepare Local Files**:
   - Create LUKS passphrase file: `./secret.key`.
   - Get host SSH key: `./keys/etc/ssh/ssh_host_ed25519_key` and `./keys/etc/ssh/ssh_host_ed25519_key.pub`

2. **Run Install**:

   ```sh
   nixos-anywhere --extra-files ./keys --flake .#ristretto --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
   ```

3. **Post-Install**:
   - Add user Age key to `~/.config/sops/age/keys.txt`).
   - Move over the GitHub SSH private key and clone the nix configuration: `git clone git@github.com:michaelbrusegard/nix-config.git ~/Projects/nix-config`.
   - For TPM auto unlock: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7+11 /dev/sda2`.

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

Now clone the nix-config repository, add the age keys and rebuild.

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

## Espresso (NixOS K3s Cluster)

The Espresso setup consists of HA k3s nodes (espresso1, espresso2, espresso3)
for running containerized homelab and business services like websites, media
hosting and automation.

sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s

### Prerequisites

Start with obtaining MAC addresses for each node by enabling PXE (Preboot
Execution Environment) and writing down the MAC address. Then disable PXE
again and assign a static IP to each node from the router.

### Bootstrap with NixOS Anywhere

```sh
nixos-anywhere --extra-files ./keys --flake .#espresso-1 --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@10.0.186.19

```

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

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p3
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/sda1
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/sdb1

sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p3
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/sda1
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/sdb1
```

### Cluster Management

- Access via `kubectl` after connecting to any node
- Drain nodes for maintenance: `kubectl drain espresso1`
- Uncordon after: `kubectl uncordon espresso1`

### NetBird VPN Bootstrap

NetBird runs as a split deployment: the control plane on the espresso cluster
and the subnet-routing peer on macchiato. The NetBird combined server uses an
embedded identity provider (IdP) for initial bootstrap. An external OIDC
provider (Pocket ID) must be added through the dashboard UI after the first
boot because the combined server does not support declarative external IdP
configuration.

1. **Verify the server is running:**

   ```sh
   kubectl get pod -n netbird
   curl https://netbird.gullhaugveien.michaelbrusegard.com/api/instance
   ```

   You want `{"setup_required":true}` and both pods `Running`.

2. **Create the first admin account:**

   Open `https://netbird.gullhaugveien.michaelbrusegard.com` from the local
   network. Use the embedded IdP to create an admin account. Use the same
   email address as your Pocket ID account.

3. **Add Pocket ID as an external OIDC provider:**

   In the NetBird dashboard, go to **Settings > Identity Providers > Add
   Identity Provider**. Select **Generic OIDC** and fill in:

   - **Name:** Pocket ID
   - **Client ID:** from Pocket ID OIDC client
   - **Client Secret:** from Pocket ID OIDC client
   - **Issuer:** `https://id.gullhaugveien.michaelbrusegard.com`

   Save, then copy the redirect URL NetBird provides back to the Pocket ID
   OIDC client callback URLs.

4. **Promote the Pocket ID user to owner:**

   Log out and log in via Pocket ID. The new user will need approval. Log
   back in as the local admin, approve the Pocket ID user under **Team >
   Users**, set the role to **Owner**, and confirm the ownership transfer.

5. **Update the dashboard env to Pocket ID (final state):**

   After verifying Pocket ID login works, update the encrypted NetBird
   dashboard secrets in `nix-secrets` to point at Pocket ID:

   ```sh
   sops nix-secrets/gitops/espresso/apps/netbird/secrets.yaml
   ```

   Change:
   - `AUTH_AUTHORITY` to `https://id.gullhaugveien.michaelbrusegard.com`
   - `AUTH_CLIENT_ID` to the Pocket ID client ID
   - `AUTH_CLIENT_SECRET` to the Pocket ID client secret

   Then set `localAuthDisabled: true` in the server `config.yaml` section of
   the same file. Commit, push, reconcile, and restart both NetBird pods.

6. **Create the macchiato setup key:**

   In the NetBird dashboard, create a reusable, auto-approve setup key for
   the router peer. Put the key into `nix-secrets/hosts/macchiato/secrets.yaml`,
   commit, push, and rebuild macchiato.

7. **Configure routes:**

   In NetBird, add network routes through macchiato for:
   - `10.0.186.0/24` (client VLAN)
   - `10.0.187.0/24` (server VLAN)
   - `10.0.188.0/24` (cluster VIPs)

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

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
[Karabiner-DriverKit-VirtualHIDDevice 6.2.0 package](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0)
manually and install it. Kanata's macOS driver integration is built against
that version's IPC; newer Karabiner DriverKit releases are not guaranteed to
work. Afterwards make sure it is enabled in System Settings, General -> Login
Items & Extensions -> Driver Extensions (At the bottom).

The Darwin module copies Kanata to `/usr/local/libexec/kanata/kanata` so macOS
Privacy grants are attached to a stable path instead of a changing Nix Store
path. Add that binary as an allowed application under Privacy & Security ->
Input Monitoring. If Kanata logs
`IOHIDDeviceOpen error: (iokit/common) not permitted`, remove any existing
Kanata entries, re-add `/usr/local/libexec/kanata/kanata` with Cmd+Shift+G in
the file picker, and also allow it under Privacy & Security -> Accessibility.

After Kanata is running, go to Keyboard -> Keyboard Shortcuts... -> Modifier
Keys. If the Karabiner DriverKit VirtualHIDDevice appears there, select it as
the keyboard. It may not appear immediately after driver activation alone; the
virtual device is created when a root client such as Kanata requests it.

## Ristretto (NixOS/Windows Desktop)

Create an installer by downloading the minimal ISO image from
[NixOS download page](https://nixos.org/download/#nixos-iso) and flashing it to
an USB drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

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
   - Add user Age key to `~/.config/sops/age/keys.txt`).
   - Clone the infrastructure configuration using the GitHub SSH private key: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra`.
   - Rebuild the configuration: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' nh os switch`.
   - TPM auto unlock is enrolled later, after Windows is installed (see [Setup TPM auto unlock](#setup-tpm-auto-unlock)). Until then, NixOS will prompt for the LUKS passphrase on boot.

### Screenshot (Ristretto)

![Screenshot 2025-04-26 at 15 07 56](https://github.com/user-attachments/assets/cd56268b-93b1-4bfd-9c1f-2a999428dd6e)

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
It then applies the modifications and flashes a USB drive.

Go through the regular windows installation. When the installer asks for a
name, enter `michaelbrusegard` (lowercase, no space) — Windows derives the
`C:\Users\<name>` folder from this field.

After installation has finished go to Windows Update and run it to make sure the
system is updated.

Also make sure to install updated drivers for the system, the download
pages for the current system can be found below:

- [Chipset and Motherboard](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/)
- [Processor and Graphics](https://www.amd.com/en/support/download/drivers.html)

Lastly enable bitlocker for additional security.

### Screenshot (Windows)

![Screenshot 2025-06-14 at 19 55 23](https://github.com/user-attachments/assets/c56e99a1-d473-4817-b2ee-eaad579ac415)

### NixOS WSL

First we need to build the NixOS WSL tarball. This can be done by running
the following command on a nix machine:

```sh
sudo nix run .#nixosConfigurations.ristretto-wsl.config.system.build.tarballBuilder
```

This produces `nixos.wsl` in the current directory. Put it on a flash
drive and copy it to the Windows machine.

Then start by installing Windows Subsystem for Linux (WSL) on Windows:

```sh
wsl --install --no-distribution
```

Reboot the computer, connect the USB drive and move the `nixos.wsl` file over, install the NixOS WSL distro:

```sh
wsl --install --from-file nixos.wsl
```

To enter the WSL environment, run:

```sh
wsl
```

Add the user Age key to `~/.config/sops/age/keys.txt`, then clone the
infra repository using the GitHub SSH private key and rebuild:

```sh
GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' \
  git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra
GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' \
  nh os switch
```

### Applying system preferences and installing packages

First run the WinUtil tool for runtime tweaks not handled by `setup.ps1`:

```sh
irm "https://christitus.com/win" | iex
```

Under Tweaks click "Ultimate Performance Profile - Enable".

In the Updates tab select "Security Settings" to prevent Windows Updates
from automatically installing updates at the worst times.

Then run the `setup.ps1` script from an **elevated PowerShell** (the script
self-checks for admin and exits otherwise). It requires the NixOS WSL
distro to be running so it can reach files via `\\wsl.localhost\NixOS\...`:

```sh
powershell -ExecutionPolicy Bypass -File \
  \\wsl.localhost\NixOS\home\michaelbrusegard\Projects\infra\windows\setup.ps1
```

The script:

- Installs winget packages (browsers, terminals, dev tools, games launchers).
- Symlinks the PowerShell 7 profile and FanControl config from WSL.
- Sets `WEZTERM_CONFIG_FILE` to the home-manager-generated `wezterm.lua`
  in WSL.
- Extracts `windows/keyboard.zip` and runs the MSKLC `setup.exe` to install
  the custom AltGr-on-US keyboard layout (edit `keyboard.klc` in MSKLC to
  modify).
- Copies the wallpaper, applies it as desktop + lock screen.
- Applies registry tweaks (dark mode, taskbar, NumLock off,
  fast key repeat, no mouse acceleration, etc.).

After running, load Voicemeeter Banana's saved layout manually — the
`desktop.xml` lives at
`\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\infra\windows\programs\voicemeeter\desktop.xml`.
In Voicemeeter use **Menu → Load Settings** and point at that file.

### Setup TPM auto unlock

Do this **after** Windows is installed and fully updated — Windows mutates
Secure Boot state, shifting PCR 7 and breaking earlier enrollments. Run
`lsblk` to map containers. `disk1` (24072T) holds three partitions —
`part1` ESP, `part2` LUKS `crypted-swap`, `part3` LUKS `crypted1` (root);
`disk2` (24057W) holds `part1` LUKS `crypted2`. All three LUKS volumes must
be enrolled — missing `crypted1` (root) is what leaves you typing the
passphrase even after enrolling the others.

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF0NC24072T-part2
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF0NC24072T-part3
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF0NC24057W-part1
```

## Forte (NixOS Laptop)

ASUS ProArt P16 (H7606WW): AMD Ryzen AI iGPU + NVIDIA RTX 5080 mobile
dGPU. Single LUKS NVMe, same install flow as Ristretto.

Create an installer by downloading the minimal ISO image from
[NixOS download page](https://nixos.org/download/#nixos-iso) and flashing it to
an USB drive using the following command:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Replace `YYY.iso` with the name of the downloaded ISO file and `/dev/XXX`
with the path to your USB drive.

Plug in the installer USB and boot to it, make sure secure boot keys are cleared or set to setup mode.
Set a temporary password using the `passwd` command for SSH access.
You can run `ip a` to find the IP address.

1. **Prepare Local Files**:
   - Create LUKS passphrase file: `./secret.key`.
   - Get host SSH key: `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`

2. **Run Install**:

   ```sh
   nixos-anywhere --extra-files ./keys --flake .#forte --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
   ```

3. **Post-Install**:
   - Add user Age key to `~/.config/sops/age/keys.txt`.
   - Clone the infrastructure configuration using the GitHub SSH private key: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra`.
   - Rebuild: `GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' nh os switch`.
   - Enroll TPM auto unlock:

     ```sh
      sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-id/nvme-MTFDKBA2T0QGN-1BN1AABGA_25194FF55405-part2
      sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-id/nvme-MTFDKBA2T0QGN-1BN1AABGA_25194FF55405-part3
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
**Important:** Setup TPM auto unlock:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-INTEL_SSDSCKKW120H6_CVLY630102UX120H-part2
```

Then deploy with colmena:

```sh
colmena apply --on macchiato
```

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

Add the admin Age key to `~/.config/sops/age/keys.txt`) to be able to decrypt
user secrets, then deploy the node with colmena (substitute the node name):

```sh
colmena apply --on espresso-0
```

Setup TPM auto unlock for all the applicable disks.

espresso-0:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB59074B-part2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB59074B-part3
```

espresso-1:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB58943B-part2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB58943B-part3
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-MZ7LM3T8HMLP0D3_S37MNX0J600459-part1
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-MZ7LM3T8HMLP0D3_S37MNX0J900816-part1
```

espresso-2:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB59076B-part2
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_500GB_S64BNF0RB59076B-part3
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-MZ7LM3T8HMLP0D3_S37MNX0J600452-part1
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-MZ7LM3T8HMLP0D3_S37MNX0J600844-part1
```

## Freddo and Manata (NixOS Raspberry Pi Backup Servers)

`freddo` (one 2TB drive) and `manata` (two 1TB drives) are Raspberry Pi 4
hosts running a restic `rest-server` as LAN backup targets. Both pool their
drives with mergerfs under `/srv/backup`, with numbered LUKS labels (`dN`), so
adding a drive later is mechanical. They are flashed from a prebuilt SD image,
not `nixos-anywhere`. The Pi has no TPM, so the external drives unlock from a
LUKS keyfile stored as a sops secret — headless, but offers no protection if
the whole Pi is stolen. Do each step per host, substituting the name.

### Format the external drives

Extract the LUKS key from `secrets.yaml` into `./secret.key` **byte-identically**
— it must match what the host mounts with at `/run/secrets/luks/key`. Use
`sops --extract` without adding a trailing newline (a stray `\n` makes the key
48 bytes here but 47 at runtime, so the drive won't unlock):

```sh
sops --decrypt --extract '["luks"]["key"]' \
  ~/Projects/infra-secrets/hosts/freddo/secrets.yaml \
  | tr -d '\n' > ./secret.key
# sanity-check: this must equal the on-host keyfile length
wc -c ./secret.key
```

Then LUKS-format each drive with the label its crypttab entry expects,
addressing the drive by its stable `/dev/disk/by-id/` path.

Freddo (single 2TB drive):

```sh
sudo cryptsetup luksFormat --label freddo-d1-crypt \
  --pbkdf argon2id --pbkdf-memory 256000 --iter-time 2000 \
  /dev/disk/by-id/usb-Seagate_Ultra_Slim_PL_NA7V527Y-0:0 ./secret.key
sudo cryptsetup open --key-file ./secret.key /dev/disk/by-id/usb-Seagate_Ultra_Slim_PL_NA7V527Y-0:0 freddo-d1
sudo mkfs.ext4 /dev/mapper/freddo-d1
```

Manata (two 1TB drives):

```sh
sudo cryptsetup luksFormat --label manata-d1-crypt \
  --pbkdf argon2id --pbkdf-memory 256000 --iter-time 2000 \
  /dev/disk/by-id/usb-WD_Elements_25A2_5758353141353841454B5956-0:0 ./secret.key
sudo cryptsetup open --key-file ./secret.key /dev/disk/by-id/usb-WD_Elements_25A2_5758353141353841454B5956-0:0 manata-d1
sudo mkfs.ext4 /dev/mapper/manata-d1

sudo cryptsetup luksFormat --label manata-d2-crypt \
  --pbkdf argon2id --pbkdf-memory 256000 --iter-time 2000 \
  /dev/disk/by-id/usb-WD_Elements_25A2_575836314135383250313754-0:0 ./secret.key
sudo cryptsetup open --key-file ./secret.key /dev/disk/by-id/usb-WD_Elements_25A2_575836314135383250313754-0:0 manata-d2
sudo mkfs.ext4 /dev/mapper/manata-d2
```

To add a drive to a host later, format it with the next number (e.g.
`freddo-d2-crypt` → `freddo-d2`, same `--pbkdf` flags), then in the host's
`hardware.nix` add its `crypttab` line, a `/mnt/diskN` mount, and append
`/mnt/diskN` to the `/srv/backup` mergerfs device string and its
`requires-mounts-for`.

### Build, inject the host key, and flash

Build on `ristretto`/`forte` (aarch64 binfmt), not `lungo`. The image is
keyless; the host key is injected afterwards via a loopback mount so it never
touches the nix store.

1. **Prepare the host key**: place it at the same path nixos-anywhere uses —
   `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and
   `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`. Ensure the private key
   is `0600`, or `ssh-keygen`/sshd reject it:

   ```sh
   chmod 600 ./keys/persistent/etc/ssh/ssh_host_ed25519_key
   ```

2. **Build the image** (substitute the host name). Decompress to a temp file
   so it is kept out of the repo and easy to clean up:

   ```sh
   nix build .#nixosConfigurations.freddo.config.system.build.sdImage
   img="$(mktemp --suffix=.img)"
   zstd -dc result/sd-image/*.img.zst > "$img"
   ```

3. **Mount the root partition** of the built image:

   ```sh
   loop="$(sudo losetup --find --partscan --show "$img")"
   mnt="$(mktemp -d)"
   sudo mount "${loop}p2" "$mnt"
   ```

4. **Inject the host key.** The NIXOS_SD partition (`p2`) mounts directly as
   `/persistent` at runtime, so a file at `$mnt/etc/ssh/...` becomes
   `/persistent/etc/ssh/...` on the booted system — do **not** add a
   `persistent/` level (that would land at `/persistent/persistent/...` and the
   key would never be found). The private key **must** be `0600 root:root`, or
   sshd rejects it and generates a different key, breaking sops decryption. Use
   `install` (a plain `cp` preserves the source's `0644`), then `sync`:

   ```sh
   sudo install -d -m 755 "$mnt/etc/ssh"
   sudo install -m 600 ./keys/persistent/etc/ssh/ssh_host_ed25519_key "$mnt/etc/ssh/ssh_host_ed25519_key"
   sudo install -m 644 ./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub "$mnt/etc/ssh/ssh_host_ed25519_key.pub"
   sudo sync
   ```

   Verify the injected key parses and its key material matches the `.pub` (a
   truncated key is silently rejected and regenerated at boot). Compare only the
   key field (field 2) since `ssh-keygen -y` and the `.pub` differ in trailing
   comment:

   ```sh
   [ "$(sudo ssh-keygen -y -f "$mnt/etc/ssh/ssh_host_ed25519_key" | cut -d' ' -f2)" \
     = "$(cut -d' ' -f2 "$mnt/etc/ssh/ssh_host_ed25519_key.pub")" ] \
     && echo "host key OK" || echo "HOST KEY MISMATCH - do not flash"
   ```

5. **Unmount, flash, and clean up** (`/dev/XXX` is the card):

   ```sh
   sudo umount "$mnt" && rmdir "$mnt" && sudo losetup -d "$loop"
   sudo dd if="$img" of=/dev/XXX bs=4M status=progress conv=fsync
   rm "$img"
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

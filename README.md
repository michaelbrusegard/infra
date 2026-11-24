# infra

This is primarily a guide for myself on how to setup my own systems, feel free
to copy anything, but do not expect a direct copy of everything to work for you.

Note to self: follow the guide for each system step by step.

> [!NOTE]
> I also maintain a private repository with a Nix flake containing soft
> and hard secrets, so building this as is will fail when it tries to fetch
> it. The private flake uses Age keys to encrypt the most critical secrets. To
> include them in the build, add the age keys to `~/.config/sops/age/keys.txt`.

## Day to day

Rebuild the machine I am sitting at:

```sh
nh os switch       # ristretto, forte, ristretto-wsl
nh darwin switch   # lungo
```

Deploy a server from my laptop:

```sh
colmena apply --on macchiato
colmena apply --on espresso-0
```

Before I commit:

```sh
nix run .#lint    # quick: formatting, lint rules, secret scan
nix flake check   # everything, including tests and all hosts
nix run .#check   # the checks that need network: kubeconform, tofu validate
```

To see what a change actually does to the machines and the cluster:

```sh
nix run .#diff-hosts -- main
nix run .#diff-manifests -- main
```

Pushing to `main` deploys `gitops/espresso` to the cluster through Flux, so I
only push when I mean it.

After changing something in `../infra-secrets` and pushing it there:

```sh
nix flake update secrets
```

A new machine needs three things: a folder under `modules/hosts/`, a folder
with the same name in `../infra-secrets/hosts/`, and its host key in
`../infra-secrets/.sops.yaml`.

## Installing a NixOS machine

Ristretto, Forte, Macchiato, Cortado and the Espresso nodes all install the
same way. The per-machine sections below only list what is different.

Create an installer by downloading the minimal ISO image from the
[NixOS download page](https://nixos.org/download/#nixos-iso) and flashing it to
an USB drive:

```sh
sudo dd if=~/Downloads/YYY.iso of=/dev/XXX bs=4M status=progress oflag=sync
```

Plug in the USB and boot to it, make sure secure boot keys are cleared or set
to setup mode. Set a temporary password using the `passwd` command for SSH
access. Run `ip a` to find the IP address. Alternatively connect the machine
directly to a Mac with "Internet Sharing" enabled.

Prepare these files in the repo folder (they are gitignored):

- The LUKS passphrase in `./secret.key`.
- The host SSH key in `./keys/persistent/etc/ssh/ssh_host_ed25519_key` and
  `./keys/persistent/etc/ssh/ssh_host_ed25519_key.pub`.

Then install. If prompted for a password, it is the temporary one from above:

```sh
nixos-anywhere --extra-files ./keys --flake .#HOST --disk-encryption-keys /tmp/secret.key ./secret.key --build-on remote nixos@IP_ADDRESS
```

After the first boot, add the Age key to `~/.config/sops/age/keys.txt` (my user
key on the desktops, the admin key on the servers).

On the desktops, clone and rebuild with the GitHub SSH private key:

```sh
GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' \
  git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra
GIT_SSH_COMMAND='ssh -i /path/to/private-key -o IdentitiesOnly=yes -F /dev/null' \
  nh os switch
```

On the servers, deploy with `colmena apply --on HOST` instead.

Last, enroll every LUKS volume for TPM auto unlock. The disks for each machine
are listed in its section. Until that is done the machine asks for the
passphrase on boot.

## Lungo (Nix-darwin Laptop)

First install macOS normally by following the default installation on the mac.
To access the installer hold the power button during boot to access recovery
options.

Install Xcode command line tools and Rosetta:

```sh
xcode-select --install
softwareupdate --install-rosetta --agree-to-license
```

Install Nix:

```sh
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

Then move away the conflicting nix configuration left by the installer, and
clean up the standalone lix launch daemon to prevent boot conflicts:

```sh
sudo mv /etc/nix/nix.custom.conf{,.before-nix-darwin}
sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
sudo launchctl bootout system /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist || true
sudo rm -f /Library/LaunchDaemons/systems.lix.nix-installer.nix-hook.plist
```

Add the GitHub SSH private key and clone:

```sh
ssh-add ./private-key
git clone git@github.com:michaelbrusegard/infra.git ~/Projects/infra
```

Put the user secrets Age key in `~/.config/sops/age/keys.txt` and build the
system the first time:

```sh
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake $HOME/Projects/infra#lungo
```

### Keyboard daemon for kanata

Download the
[Karabiner-DriverKit-VirtualHIDDevice 6.2.0 package](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0)
manually and install it. Kanata's macOS driver integration is built against
that version's IPC; newer Karabiner DriverKit releases are not guaranteed to
work. Afterwards make sure it is enabled in System Settings, General -> Login
Items & Extensions -> Driver Extensions (at the bottom).

The Darwin module copies Kanata into `/Applications/Kanata.app` so macOS Privacy
grants are attached to a stable app bundle instead of a changing Nix Store path.
It is signed with a machine-local certificate (`Kanata Local Code Signing` in
the System keychain, created on first activation) so the grants survive kanata
rebuilds. Add that app as an allowed application under Privacy & Security ->
Input Monitoring. If Kanata logs
`IOHIDDeviceOpen error: (iokit/common) not permitted`, remove any existing
Kanata entries, re-add `/Applications/Kanata.app` with Cmd+Shift+G in the file
picker, and also allow it under Privacy & Security -> Accessibility. Kanata only
opens keyboards at startup, so restart it after granting:
`sudo launchctl kickstart -k system/org.nixos.kanata`.

After Kanata is running, go to Keyboard -> Keyboard Shortcuts... -> Modifier
Keys. If the Karabiner DriverKit VirtualHIDDevice appears there, select it as
the keyboard. It may not appear immediately after driver activation alone; the
virtual device is created when a root client such as Kanata requests it.

## Ristretto (NixOS/Windows Desktop)

Install NixOS first with `--flake .#ristretto`, then Windows next to it. TPM
auto unlock comes last, see [Setup TPM auto unlock](#setup-tpm-auto-unlock).

### Create Windows installer

To create the installation ISO for Windows, I use Chris Titus Tech's Windows
Utility to create a clean telemetry-free ISO that does not require a Microsoft
account (this has to be run on a Windows machine or in a VM). The commands
require administrator privileges, so run PowerShell as administrator.

First, enable execution of scripts in PowerShell, then load the tool:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm "https://christitus.com/win" | iex
```

In the tool download the newest Windows ISO image from Microsoft. It then
applies the modifications and flashes a USB drive.

Go through the regular windows installation. When the installer asks for a
name, enter `michaelbrusegard` (lowercase, no space), since Windows derives the
`C:\Users\<name>` folder from this field.

After installation has finished go to Windows Update and run it to make sure the
system is updated. Also install updated drivers:

- [Chipset and Motherboard](https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-viii-impact-model/helpdesk_download/)
- [Processor and Graphics](https://www.amd.com/en/support/download/drivers.html)

Lastly enable bitlocker for additional security.

### NixOS WSL

Build the NixOS WSL tarball on a nix machine:

```sh
sudo nix run .#nixosConfigurations.ristretto-wsl.config.system.build.tarballBuilder
```

This produces `nixos.wsl` in the current directory. Put it on a flash drive and
copy it to the Windows machine.

Then install Windows Subsystem for Linux (WSL) on Windows:

```sh
wsl --install --no-distribution
```

Reboot the computer, move the `nixos.wsl` file over and install the distro:

```sh
wsl --install --from-file nixos.wsl
```

Enter it with `wsl`, add the user Age key to `~/.config/sops/age/keys.txt`,
then clone and rebuild the same way as on the desktops.

### Applying system preferences and installing packages

First run the WinUtil tool for runtime tweaks not handled by `setup.ps1`:

```sh
irm "https://christitus.com/win" | iex
```

Under Tweaks click "Ultimate Performance Profile - Enable".

In the Updates tab select "Security Settings" to prevent Windows Updates
from automatically installing updates at the worst times.

Then run the `setup.ps1` script from an **elevated PowerShell** (the script
checks for admin itself and exits otherwise). It requires the NixOS WSL
distro to be running so it can reach files via `\\wsl.localhost\NixOS\...`:

```sh
powershell -ExecutionPolicy Bypass -File \
  \\wsl.localhost\NixOS\home\michaelbrusegard\Projects\infra\windows\setup.ps1
```

The script:

- Installs winget packages (browsers, terminals, dev tools, games launchers).
- Symlinks the PowerShell 7 profile and FanControl config from WSL.
- Extracts `windows/keyboard.zip` and runs the MSKLC `setup.exe` to install
  the custom AltGr-on-US keyboard layout (edit `keyboard.klc` in MSKLC to
  modify).
- Copies the wallpaper, applies it as desktop + lock screen.
- Applies registry tweaks (dark mode, taskbar, NumLock off,
  fast key repeat, no mouse acceleration, etc.).

After running, load Voicemeeter Banana's saved layout manually. The
`desktop.xml` lives at
`\\wsl.localhost\NixOS\home\michaelbrusegard\Projects\infra\windows\programs\voicemeeter\desktop.xml`.
In Voicemeeter use **Menu → Load Settings** and point at that file.

### Setup TPM auto unlock

Do this **after** Windows is installed and fully updated. Windows mutates
Secure Boot state, shifting PCR 7 and breaking earlier enrollments. Run
`lsblk` to map containers. `disk1` (24072T) holds three partitions:
`part1` ESP, `part2` LUKS `crypted-swap`, `part3` LUKS `crypted1` (root).
`disk2` (24057W) holds `part1` LUKS `crypted2`. All three LUKS volumes must
be enrolled. Missing `crypted1` (root) is what leaves me typing the
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
dGPU. Single LUKS NVMe. Install with `--flake .#forte`, then enroll TPM auto
unlock:

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-id/nvme-MTFDKBA2T0QGN-1BN1AABGA_25194FF55405-part2
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-id/nvme-MTFDKBA2T0QGN-1BN1AABGA_25194FF55405-part3
```

## Macchiato (NixOS Router)

Install with `--flake .#macchiato`. **Important:** setup TPM auto unlock before
leaving it headless:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/ata-INTEL_SSDSCKKW120H6_CVLY630102UX120H-part2
```

## Cortado (NixOS Router)

Install with `--flake .#cortado`, then:

```sh
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  /dev/disk/by-id/nvme-TWSC_TSC3AN128-H2T70S_TTSFA258HX00212-part2
```

Port 6 is WAN. Ports 1–5 are the `10.0.15.0/24` LAN, with Cortado at
`10.0.15.1`.

## Espresso (NixOS K3S Cluster)

The Espresso setup consists of the nodes espresso-0, espresso-1 and espresso-2
in a k3s cluster, so the install has to be done for each of the nodes with
`--flake .#espresso-NODE`. It is important to do espresso-0 first so the
cluster is bootstrapped.

Then TPM auto unlock for all the disks.

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
LUKS keyfile stored as a sops secret. That works headless, but offers no
protection if the whole Pi is stolen. Do each step per host, substituting the
name.

### Format the external drives

Extract the LUKS key from `secrets.yaml` into `./secret.key` **byte-identically**.
It must match what the host mounts with at `/run/secrets/luks/key`. Use
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

1. **Prepare the host key**: place it at the same path nixos-anywhere uses,
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
   `/persistent/etc/ssh/...` on the booted system. Do **not** add a
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

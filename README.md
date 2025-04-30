# Dotfiles

This is primarily a guide for myself on how to setup my own systems, feel free to copy any of the dotfiles, but do not expect a direct copy of everything to work for you.

Make sure to follow the guide for each system step by step and to move over an SSH key for GitHub to get started with cloning the repository.
Then, clone the repository into `~/Developer/dotfiles` using SSH:

```zsh
git clone git@github.com:michaelbrusegard/dotfiles.git ~/Developer/dotfiles
```

> [!NOTE]
> I also maintain a private repository with encrypted secrets that is added into the repository as a Nix flake. Directly copying the dotfiles will therefore most likely fail since it will fail to fetch the private repository.

## Reference links

- [nixpkgs](https://mynixos.com/nixpkgs/options)
- [nix-darwin](https://mynixos.com/nix-darwin/options)
- [home-manager](https://mynixos.com/home-manager/options)

## Desktop (NixOS)

### Screenshots

![2025-04-26_15-07-56](https://github.com/user-attachments/assets/cd56268b-93b1-4bfd-9c1f-2a999428dd6e)

## Darwin systems

First install MacOS normally by following the instructions on the screen.

### Disabling SIP

System Integrity Protection (SIP) needs to be partially disabled for the [yabai](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) tiling window manager to work correctly.

1. Turn off the mac, then press and hold the power button until "Loading startup options" appears.
   Click Options, then click Continue.

2. In the menu bar, choose `Utilities`, then `Terminal`

3. Run this:

```sh
csrutil enable --without fs --without debug --without nvram
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

### Screenshots

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

- Andrey0189's [Nix Hyprland configuration](https://github.com/Andrey0189/nixos-config-reborn/tree/master/home-manager/modules/hyprland)
- Notusknot's [nix-dotfiles](https://github.com/notusknot/dotfiles-nix)
- Mathias Bynens and his [MacOS defaults](https://github.com/mathiasbynens/dotfiles/blob/main/.macos)
- Dries Vints and his [SSH script](https://github.com/driesvints/dotfiles/blob/main/ssh.sh)
- Antione Martin and his [GPG script](https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh)
- Elliot's fast and beautiful [.zshrc prompt](https://github.com/dreamsofautonomy/zensh/blob/main/.zshrc)
- [Michael Bao's dotfiles](https://github.com/tcmmichaelb139/.dotfiles)
- [Josean Martinez's dotfiles](https://github.com/josean-dev/dev-environment-files)
- [TheBlueRuby's awesome Arch Linux setup](https://github.com/TheBlueRuby/dotfiles-arch)
- [XLNC](https://github.com/naveenkrdy)

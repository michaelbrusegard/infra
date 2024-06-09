# Dotfiles

To get started, clone the repository into the home directory:

```zsh
git clone https://github.com/michaelbrusegard/dotfiles.git ~/dotfiles
```

## MacOS

Before setting up MacOS, System Intergrity Protection (SIP) needs to be partially disabled for the [yabai](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection) tiling window manager to work correctly.

1. Turn off the mac, then press and hold the power button until "Loading startup options" appears.
   Click Options, then click Continue.

2. In the menu bar, choose `Utilities`, then `Terminal`

3. Run this:

```zsh
csrutil enable --without fs --without debug --without nvram
```

Then go through each script below making sure it completes correctly before running the next.

### Installing apps & utilities using homebrew

```zsh
zsh ~/dotfiles/macos/scripts/brew.zsh
```

### Setting sensible system settings for MacOS

```zsh
zsh ~/dotfiles/macos/scripts/defaults.zsh
```

### Creating symlinks for the config files

```zsh
cd ~/dotfiles && stow macos
```

### Setup login items

```zsh
zsh ~/dotfiles/macos/scripts/login.zsh
```

## Other scripts

[Generate new SSH key for GitHub](https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) by running:

```zsh
zsh ~/dotfiles/shared/scripts/ssh.zsh
```

[Generating a new GPG key for GitHub](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key) by running:

```zsh
zsh ~/dotfiles/shared/scripts/gpg.zsh
```

When finished switch to use SSH for the repository:

```zsh
cd ~/dotfiles && git remote set-url origin git@github.com:michaelbrusegard/dotfiles.git
```

## Inspiration…

- Mathias Bynens and his [macOS defaults](https://github.com/mathiasbynens/dotfiles/blob/main/.macos)
- Dries Vints and his [SSH script](https://github.com/driesvints/dotfiles/blob/main/ssh.sh)
- Antione Martin and his [GPG script](https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh)
- Elliot's fast and beautiful [.zshrc prompt](https://github.com/dreamsofautonomy/zensh/blob/main/.zshrc)
- [Michael Bao's dotfiles](https://github.com/tcmmichaelb139/.dotfiles)
- [Josean Martinez's dotfiles](https://github.com/josean-dev/dev-environment-files)
- [TheBlueRuby's awesome Arch Linux setup](https://github.com/TheBlueRuby/dotfiles-arch)
- [XLNC](https://github.com/naveenkrdy)

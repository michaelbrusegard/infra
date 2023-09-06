## Introduction

These are my dotfiles. Take anything you want, but at your own risk. Remember to review the code and remove things you don't want or need. Everything is seperated into scripts, for a new machine I would recommend running the scripts in the order given below. The symlink script will symlink all the dotfiles to the home directory. While the macos and brew scripts are mostly for setting up a new machine. The ssh and gpg scripts are for generating new keys for GitHub and can be useful regardless.

## Scripts

Set sensible macOS default settings:

```zsh
sh ./scripts/macos.sh
```

Symlink dotfiles from home directory:

```zsh
sh ./scripts/symlink.sh
```

Install apps and command line utilities:

```zsh
sh ./scripts/brew.sh
```

[Generate new SSH key for GitHub](https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) by running:

```zsh
sh ./scripts/ssh.sh
```

[Generating a new GPG key for GitHub](https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key) by running:

```zsh
sh ./scripts/gpg.sh
```

## Thanks to…

- Mathias Bynens and his aliases + macOS defaults from his [dotfiles](https://github.com/mathiasbynens/dotfiles)
- Dries Vints and his [SSH script](https://github.com/driesvints/dotfiles/blob/main/ssh.sh)
- Antione Martin and his [GPG script](https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh)
- Idea to use symlinks instead of copying from [XLNC](https://github.com/naveenkrdy)

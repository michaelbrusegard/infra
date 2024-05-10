#!/usr/bin/env bash

set -e  # Abort the script if any command fails

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."  # Get the absolute path to the repository directory

# Delete existing dotfiles in the home directory
rm -rf ~/.zshrc ~/.p10k.zsh ~/.tmux.conf ~/.aliases ~/.gitconfig ~/.aerospace.toml &>/dev/null || true


# Create symlinks for each dotfile
ln -sf "${repo_dir}/.zshrc" ~/.zshrc
ln -sf "${repo_dir}/.p10k.zsh" ~/.p10k.zsh
ln -sf "${repo_dir}/.tmux.conf" ~/.tmux.conf
ln -sf "${repo_dir}/.aliases" ~/.aliases
ln -sf "${repo_dir}/.gitconfig" ~/.gitconfig
ln -sf "${repo_dir}/.aerospace.toml" ~/.aerospace.toml

echo "Symlinks created successfully!"
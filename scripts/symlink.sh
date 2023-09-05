#!/usr/bin/env bash

set -e  # Abort the script if any command fails

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."  # Get the absolute path to the repository directory

# Delete existing dotfiles in the home directory
rm -rf ~/.zshrc ~/.aliases ~/.functions ~/.gitconfig ~/.config &>/dev/null || true


# Create symlinks for each dotfile
ln -sf "${repo_dir}/.zshrc" ~/.zshrc
ln -sf "${repo_dir}/.aliases" ~/.aliases
ln -sf "${repo_dir}/.functions" ~/.functions
ln -sf "${repo_dir}/.gitconfig" ~/.gitconfig
ln -sf "${repo_dir}/.config" ~/.config

echo "Symlinks created successfully!"
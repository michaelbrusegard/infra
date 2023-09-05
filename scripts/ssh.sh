#!/usr/bin/env bash

set -e  # Abort the script if any command fails

# Thanks to driesvints for most parts of this script!
# ~/ssh.sh — https://github.com/driesvints/dotfiles/blob/main/ssh.sh

echo "Generating a new SSH key for GitHub..."

printf "Enter user email: "
read USER_EMAIL

echo "Using user email $USER_EMAIL"

# Generating a new SSH key
# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
ssh-keygen -t ed25519 -C "${USER_EMAIL}" -f ~/.ssh/id_ed25519

# Adding your SSH key to the ssh-agent
# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent
eval "$(ssh-agent -s)"

touch ~/.ssh/config
echo "Host github.com\n AddKeysToAgent yes\n UseKeychain yes\n IdentityFile ~/.ssh/id_ed25519" | tee ~/.ssh/config

ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Adding your SSH key to your GitHub account
# https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account#adding-a-new-ssh-key-to-your-account
pbcopy < ~/.ssh/id_ed25519.pub
echo "The SSH key has been copied to the clipboard."
echo "Please go to your GitHub account settings and add the SSH key."
echo "Opening link in 5 seconds..."
sleep 5
open "https://github.com/settings/keys"
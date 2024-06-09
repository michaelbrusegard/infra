#!/usr/bin/env zsh

set -e  # Abort the script if any command fails

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Install Homebrew if it is not already installed
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install everything specified in the brewfile
brew bundle --file="$(dirname "$PWD")/resources/Brewfile"

# Cleanup
brew cleanup

echo "Done. All apps should be installed."

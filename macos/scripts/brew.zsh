#!/usr/bin/env zsh

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Install Homebrew if it is not already installed
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install everything specified in the brewfile
/opt/homebrew/bin/brew bundle --file="$(dirname "$(realpath "$0")")/../resources/Brewfile"

# Install local casks
/opt/homebrew/bin/brew install --cask "$(dirname "$(realpath "$0")")/../resources/yabaiindicator.rb"

# Cleanup
/opt/homebrew/bin/brew cleanup

echo "Done. All apps should be installed."

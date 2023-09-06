#!/usr/bin/env bash

set -e  # Abort the script if any command fails

# Install Homebrew if it is not already installed
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Run brew bundle with the specified Brewfile path
BREWFILE_PATH="$SCRIPT_DIR/../resources/Brewfile"
brew bundle --file "$BREWFILE_PATH"

# Check if entry exists in gpg-agent.conf before adding it
if ! grep -q "^pinentry-program" ~/.gnupg/gpg-agent.conf ; then
    echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
    killall gpg-agent
fi

brew cleanup
echo "Done. All apps should be installed."
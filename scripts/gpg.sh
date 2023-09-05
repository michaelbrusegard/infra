#!/usr/bin/env bash

set -e  # Abort the script if any command fails

# Thanks to antoinemartin for inspiration for this script!
# ~/create_gpg_key.sh — https://github.com/antoinemartin/create-gpg-key/blob/main/create_gpg_key.sh

# Read secret string
read_secret()
{
    # Disable echo.
    stty -echo

    # Set up trap to ensure echo is enabled before exiting if the script
    # is terminated while echo is disabled.
    trap 'stty echo' EXIT

    # Read secret.
    read "$@"

    # Enable echo.
    stty echo
    trap - EXIT

    # Print a newline because the newline entered by the user after
    # entering the passcode is not echoed. This ensures that the
    # next line of output begins at a new line.
    echo
}

echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf

echo "Generating a new GPG key for GitHub..."

printf "Enter user name: "
read USER_NAME
printf "Enter user email: "
read USER_EMAIL

USER_ID="${USER_NAME} <${USER_EMAIL}>"
echo "Using user id $USER_ID"

printf "Enter password (hard to guess, easy to remember and use): "
read_secret PASSWORD
printf "Enter again for confirmation: "
read_secret PASSWORD_CONFIRMATION

if [ "$PASSWORD" != "$PASSWORD_CONFIRMATION" ]; then 
    echo "ERROR! Passwords don't match. Please restart"
    exit 1
fi

# Generating a new GPG key
# https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key#generating-a-gpg-key
gpg --batch --passphrase "$PASSWORD" --quick-generate-key "${USER_ID}" rsa4096 sign 0

EXPORTED_KEY=$(gpg --armor --export ${USER_EMAIL})

# Adding your GPG key to your GitHub account
# https://docs.github.com/en/authentication/managing-commit-signature-verification/adding-a-gpg-key-to-your-github-account#adding-a-gpg-
echo "$EXPORTED_KEY" | pbcopy
echo "The GPG key has been copied to the clipboard."
echo "Please go to your GitHub account settings and add the GPG key."
echo "Opening link in 5 seconds..."
sleep 5
open "https://github.com/settings/keys"
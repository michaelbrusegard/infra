#!/usr/bin/env zsh

set -e  # Abort the script if any command fails

# Function to read secret input
read_secret() {
    # Disable echo.
    stty -echo

    # Set up trap to ensure echo is enabled before exiting if the script is terminated while echo is disabled.
    trap 'stty echo' EXIT

    # Read secret.
    read "$@"

    # Enable echo.
    stty echo
    trap - EXIT

    # Print a newline because the newline entered by the user after entering the passcode is not echoed.
    echo
}

printf "Enter user email: "
read USER_EMAIL
printf "Enter user name: "
read USER_NAME

USER_ID="${USER_NAME} <${USER_EMAIL}>"
echo "Using user id $USER_ID"

printf "Enter password: "
read_secret PASSWORD
printf "Enter again for confirmation: "
read_secret PASSWORD_CONFIRMATION

if [ "$PASSWORD" != "$PASSWORD_CONFIRMATION" ]; then 
    echo "ERROR! Passwords don't match. Please restart."
    exit 1
fi

# Generating a new GPG key
gpg --batch --passphrase "$PASSWORD" --quick-generate-key "$USER_ID" rsa4096 sign 0

# Export the generated GPG key
EXPORTED_KEY=$(gpg --armor --export "$USER_EMAIL")

# Add your GPG key to your GitHub account
echo "$EXPORTED_KEY" | pbcopy
echo "The GPG key has been copied to the clipboard."
echo "Please go to your GitHub account settings and add the GPG key."
echo "Opening link in 5 seconds..."

sleep 5

open "https://github.com/settings/keys"


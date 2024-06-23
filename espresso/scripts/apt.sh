#!/bin/bash

set -x  # Print commands and their arguments as they are executed

# Update package list
sudo apt-get update

# Upgrade all packages
sudo apt-get dist-upgrade -y

# Install dselect
sudo apt-get install dselect

# Install packages from PackageFile
sudo dpkg --set-selections < ../resources/PackageFile
sudo apt-get dselect-upgrade

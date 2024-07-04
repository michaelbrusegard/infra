#!/bin/bash

set -x  # Print commands and their arguments as they are executed

# Enable SSH
sudo systemctl enable ssh

# Enable wake on lan
sudo systemctl enable wol.service

#!/bin/bash

set -x  # Print commands and their arguments as they are executed

# Enable wake on lan
sudo systemctl enable wol.service

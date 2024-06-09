#!/usr/bin/env zsh

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Recording current settings...${NC}"

old_settings_file=$(mktemp)
defaults read > "$old_settings_file"

old_host_settings_file=$(mktemp)
defaults -currentHost read > "$old_host_settings_file"

echo -e "${GREEN}Change settings and press any key to continue${NC}"

read -r

echo -e "${BLUE}Recording new settings...${NC}"

new_settings_file=$(mktemp)
defaults read > "$new_settings_file"

new_host_settings_file=$(mktemp)
defaults -currentHost read > "$new_host_settings_file"

clear

echo -e "${YELLOW}Diff of global settings:${NC}"
git --no-pager diff --no-index -U15 "$old_settings_file" "$new_settings_file"

echo -e "${YELLOW}Diff of current host settings:${NC}"
git --no-pager diff --no-index -U15 "$old_host_settings_file" "$new_host_settings_file"

rm "$old_settings_file" "$old_host_settings_file" "$new_settings_file" "$new_host_settings_file"

echo -e "${GREEN}After you find the key with your options, simply run defaults find \${keyname} to find the domain it is saved in.${NC}"

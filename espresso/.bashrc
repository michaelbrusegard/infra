# Prompt
update_prompt() {
    if [[ $1 == "insert" ]]; then
        PS1='\[\e[34m\]\w\[\e[0m\]\n\[\e[1;32m\]❮ \[\e[0m\]'
    else
        PS1='\[\e[34m\]\w\[\e[0m\]\n\[\e[1;32m\]❯ \[\e[0m\]'
    fi
}
update_prompt "normal"
bind 'set show-mode-in-prompt on'
bind 'set vi-ins-mode-string ""'
bind 'set vi-cmd-mode-string ""'
trap 'update_prompt insert' SIGUSR1
trap 'update_prompt normal' SIGUSR2
switch_to_insert_mode() {
    update_prompt "insert"
    kill -SIGUSR1 $$
}
switch_to_normal_mode() {
    update_prompt "normal"
    kill -SIGUSR2 $$
}

bind 'set show-mode-in-prompt on'
bind 'set vi-ins-mode-string ""'
bind 'set vi-cmd-mode-string ""'
trap 'update_prompt insert' SIGUSR1
trap 'update_prompt normal' SIGUSR2

# Keybindings
set -o vi
bind -m vi-command '"k": history-search-backward'
bind -m vi-command '"j": history-search-forward'
bind '"\C-n": history-search-forward'
bind '"\C-p": history-search-backward'

# History
HISTSIZE=4200
HISTFILESIZE=4200
HISTFILE=~/.bash_history
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
export PROMPT_COMMAND="history -a; history -n; $PROMPT_COMMAND"

# Generic
export LANG=en_GB.UTF-8
export EDITOR="nvim"

# Shortcuts
alias vi='vim'
alias nvim='vim'
alias c='clear'
alias reload='source ~/.bashrc'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias -- -="cd -"

# Utilities
alias packagefile='dpkg --get-selections > ~/dotfiles/espresso/resources/PackageFile'

# Prompt
PS1='\[\e[34m\]\w\[\e[0m\]\n\[\e[1;32m\]❯ \[\e[0m\]'

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

# Aliases
if [ -f ~/.aliases_private ]; then
  source ~/.aliases_private
fi

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
alias ls='ls -a -1 --color=auto'

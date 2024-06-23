# Enable Powerlevel10k instant prompt, should stay close to the top of ~/.zshrc
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Set the directory to store Zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit if it is not there
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"

# Load Zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add in Powerlevel10k
zinit ice depth=1
zinit light romkatv/powerlevel10k

# Prompt
[[ ! -f ~/.config/powerlevel10k/p10k.zsh ]] || source ~/.config/powerlevel10k/p10k.zsh

# Load completions
autoload -Uz compinit && compinit

# Add in zsh plugins
zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::command-not-found
zinit snippet OMZP::gradle

# Apply zinit cdreplay
zinit cdreplay -q

# Keybindings
bindkey -v
bindkey -M vicmd "k" history-search-backward
bindkey -M vicmd "j" history-search-forward
bindkey "^N" history-search-forward
bindkey "^P" history-search-backward
bindkey "^Y" autosuggest-accept
bindkey "^@" autosuggest-accept
bindkey "^E" autosuggest-clear

# History
HISTSIZE=6900
HISTFILESIZE=6900
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ":completion:*" matcher-list "m:{a-z}={A-Za-z}"
zstyle ":completion:*" menu no
zstyle ":fzf-tab:complete:cd:*" fzf-preview "eza -a --tree --color=always $realpath | head -n 200"
zstyle ":fzf-tab:complete:(unset|export):*" fzf-preview "eval echo $realpath"
zstyle ":fzf-tab:complete:ssh:*" fzf-preview "dig $realpath"
zstyle ":fzf-tab:complete:*" fzf-preview "if [[ -d $realpath ]]; then eza -a --tree --color=always $realpath | head -n 200; else bat --style=plain --color=always --line-range=:500 $realpath; fi"

# Aliases
source ~/.aliases
if [ -f ~/.aliases_private ]; then
    source ~/.aliases_private
fi

# Generic
export LANG=en_GB.UTF-8
export EDITOR="nvim"

# gpg
export GPG_TTY=$TTY

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
export FZF_CTRL_T_OPTS="--preview 'if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi'"
export FZF_ALT_C_COMMAND=""
eval "$(fzf --zsh)"

# zoxide
eval "$(zoxide init --cmd cd zsh)"

# eza
alias ls="eza -a -1 --icons=always --color=always --git"

# bat
alias cat="bat"
export BAT_THEME="Catppuccin Mocha"

# thefuck
eval $(thefuck --alias)

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
[ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# jenv
export PATH="$HOME/.jenv/bin:$PATH"
eval "$(jenv init -)"

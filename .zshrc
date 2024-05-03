# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"
CASE_SENSITIVE="true"
ENABLE_CORRECTION="true"

# Update automatically without asking
zstyle ':omz:update' mode auto

plugins=(
  aliases
  colored-man-pages
  docker
  docker-compose
  fzf
  git
  gradle
  macos
  thefuck
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# User configuration
export LANG=en_GB.UTF-8
export EDITOR='nvim'

# Load aliases
source ~/.aliases

# Zoxide
eval "$(zoxide init --cmd cd zsh)"

# Avoid issues with `gpg` when installed via Homebrew
export GPG_TTY=$TTY

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# PyEnv
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Jabba
  [ -s "/opt/homebrew/opt/jabba/share/jabba/jabba.sh" ] && . "/opt/homebrew/opt/jabba/share/jabba/jabba.sh"

# Dotnet
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"

# PATH for Google Cloud SDK
source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"

# Enables shell command completion for gcloud
source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"

# Path for Android SDK
export PATH=$PATH:/opt/homebrew/share/android-commandlinetools/emulator:/opt/homebrew/share/android-commandlinetools/platform-tools

# To customize prompt, run `p10k configure` or edit ~/Projects/dotfiles/.p10k.zsh.
[[ ! -f ~/Projects/dotfiles/.p10k.zsh ]] || source ~/Projects/dotfiles/.p10k.zsh

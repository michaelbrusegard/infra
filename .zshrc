# Prompt
PROMPT='%(?.%F{green}√.%F{red}?)%f %B%F{240}%2~%f%b %# '
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
RPROMPT=\$vcs_info_msg_0_
zstyle ':vcs_info:git:*' formats '%B%F{red}(%b)%r%f'
zstyle ':vcs_info:*' enable 

# Make nano the default editor.
export EDITOR='nano';

# Prefer British English and use UTF-8.
export LANG='en_GB.UTF-8';
export LC_ALL='en_GB.UTF-8';

# Avoid issues with `gpg` as installed via Homebrew
export GPG_TTY=$(tty);

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
  [ -s "/usr/local/opt/nvm/nvm.sh" ] && \. "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/usr/local/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/usr/local/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# PyEnv
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Java Version Manager
  [ -s "/usr/local/opt/jabba/share/jabba/jabba.sh" ] && . "/usr/local/opt/jabba/share/jabba/jabba.sh"

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/michaelbrusegard/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/michaelbrusegard/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/michaelbrusegard/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/michaelbrusegard/google-cloud-sdk/completion.zsh.inc'; fi

# Load aliases and functions
source ~/.aliases
source ~/.functions
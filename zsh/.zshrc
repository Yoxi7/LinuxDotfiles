# ==============================================================================
# RETRO SAKURA / MINIMAL PIXEL - ZSH CONFIGURATION
# ==============================================================================

# User binaries in PATH
export PATH="$HOME/.local/bin:$PATH"

# History settings
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY          # Share command history between open terminals
setopt HIST_IGNORE_DUPS       # Do not record an entry that was just recorded
setopt HIST_IGNORE_ALL_DUPS   # Delete old duplicates if a command is repeated
setopt HIST_REDUCE_BLANKS     # Remove unnecessary blanks from command lines
setopt EXTENDED_HISTORY       # Write the history file in the ":start:elapsed;command" format

# Completion system
autoload -Uz compinit && compinit -C
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case-insensitive completion
zstyle ':completion:*' menu select

# Arch Linux plugins
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null

# Autosuggestion color (Muted gray-purple)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#888899'

# FZF integration (fuzzy history search on Ctrl+R, directory search on Alt+C)
if [ -f /usr/share/fzf/key-bindings.zsh ]; then
    source /usr/share/fzf/key-bindings.zsh
    source /usr/share/fzf/completion.zsh
fi

# Useful aliases
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias grep='grep --color=auto'
alias fm='files'

# Initialize Starship prompt
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# =============================================================================
# ZSH — Arch Linux workstation
# =============================================================================

# Interactive shells only
[[ -o interactive ]] || return


# -----------------------------------------------------------------------------
# Editor
# -----------------------------------------------------------------------------

export EDITOR="zeditor --wait"
export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"


# -----------------------------------------------------------------------------
# Pager
# -----------------------------------------------------------------------------

export PAGER="less"
export MANPAGER="less -R"
export LESS="-R"


# -----------------------------------------------------------------------------
# PATH
# -----------------------------------------------------------------------------

# Prevent duplicate PATH entries
typeset -U path PATH

[[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)
[[ -d "$HOME/.cargo/bin" ]] && path=("$HOME/.cargo/bin" $path)


# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------

typeset -g ZSH_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
mkdir -p -m 700 "$ZSH_STATE_DIR"
HISTFILE="$ZSH_STATE_DIR/history"
HISTSIZE=50000
SAVEHIST=50000

# Store timestamps and duration
setopt EXTENDED_HISTORY

# Remove old duplicates first when history fills up
setopt HIST_EXPIRE_DUPS_FIRST

# Do not show duplicates during history search
setopt HIST_FIND_NO_DUPS

# Remove older duplicate when a command is entered again
setopt HIST_IGNORE_ALL_DUPS

# Commands starting with a space are not persisted
setopt HIST_IGNORE_SPACE

# Clean unnecessary whitespace
setopt HIST_REDUCE_BLANKS

# Do not save duplicates to disk
setopt HIST_SAVE_NO_DUPS

# Let me edit expanded history before executing it
setopt HIST_VERIFY

# Share history between terminal sessions
setopt SHARE_HISTORY


# -----------------------------------------------------------------------------
# Shell behaviour
# -----------------------------------------------------------------------------

# cd by typing a directory directly
setopt AUTO_CD

# Keep directory stack automatically
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# Allow comments in interactive terminal
setopt INTERACTIVE_COMMENTS

# No annoying terminal beep
unsetopt BEEP


# -----------------------------------------------------------------------------
# Key bindings
# -----------------------------------------------------------------------------

# Emacs-style shortcuts
bindkey -e


# -----------------------------------------------------------------------------
# Completion
# -----------------------------------------------------------------------------

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

mkdir -p "$XDG_CACHE_HOME/zsh"

zmodload zsh/complist

autoload -Uz compinit

compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

# Interactive completion menu
zstyle ':completion:*' menu select

# Group completion results
zstyle ':completion:*' group-name ''

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Enable completion cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"


# -----------------------------------------------------------------------------
# fzf
# -----------------------------------------------------------------------------

if (( $+commands[fzf] )); then
    export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border --info=inline"

    export FZF_CTRL_T_OPTS="--walker-skip .git,node_modules,target,.next,dist"

    # fzf's --zsh integration emits a harmless but noisy
    # "can't change option: zle" on every shell start (upstream quirk in
    # its local-options save/restore idiom, still present as of fzf
    # 0.74.3) - silence it, don't hide anything else.
    source <(fzf --zsh) 2>/dev/null
fi


# -----------------------------------------------------------------------------
# zoxide
# -----------------------------------------------------------------------------

if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh)"
fi


# -----------------------------------------------------------------------------
# Zed
# -----------------------------------------------------------------------------

# Zsh ships its own function called "zed".
# Remove it so "zed" means the Zed editor.
unfunction zed 2>/dev/null

alias zed="zeditor"
alias zw="zeditor --wait"


# -----------------------------------------------------------------------------
# Modern CLI
# -----------------------------------------------------------------------------

# Arch's global Zsh config may define ls; keep the standard command available.
unalias ls 2>/dev/null
alias ll="eza -lah --icons --git --group-directories-first"
alias la="eza -a --icons --group-directories-first"
alias lt="eza --tree --level=2 --icons --group-directories-first"

alias c="clear"

# Deliberately DO NOT replace cat or grep globally.
# Use bat and rg directly.

if (( $+commands[bat] )); then
    export BAT_THEME="Catppuccin Mocha"
fi


# -----------------------------------------------------------------------------
# Arch Linux
# -----------------------------------------------------------------------------

alias update="sudo pacman -Syu"

# Keep recent package versions instead of nuking the entire pacman cache
alias cleanup="sudo paccache -r"

alias orphaned="pacman -Qdtq"


# -----------------------------------------------------------------------------
# Git
# -----------------------------------------------------------------------------

alias g="git"
alias gs="git status"
alias ga="git add"
alias gaa="git add --all"

alias gc="git commit"
alias gca="git commit --amend"

alias gp="git push"
alias gpl="git pull --rebase"

alias gd="git diff"
alias gds="git diff --staged"

alias gb="git branch"
alias gsw="git switch"
alias grs="git restore"

alias gl="git log --oneline --graph --decorate --all"


# -----------------------------------------------------------------------------
# Useful functions
# -----------------------------------------------------------------------------

mkcd() {
    [[ -z "$1" ]] && return 1

    mkdir -p -- "$1" && cd -- "$1"
}
# -----------------------------------------------------------------------------
# AI Coding Agents
# -----------------------------------------------------------------------------

# Claude Code
# cc = full permissions / no confirmation prompts
cc() {
    command claude --dangerously-skip-permissions "$@"
}

# Claude Code — normal/safe mode
alias cla="claude"

# Claude Code — continue last conversation
ccc() {
    command claude --dangerously-skip-permissions --continue "$@"
}

# Claude Code — plan mode
ccp() {
    command claude --permission-mode plan "$@"
}


# Codex
# cx = full access / no approval prompts / no sandbox
cx() {
    command codex --dangerously-bypass-approvals-and-sandbox "$@"
}

# Codex — normal/safe mode
alias cdx="codex"

# Codex — resume
cxr() {
    command codex --dangerously-bypass-approvals-and-sandbox resume "$@"
}

# Codex — auto-review permissions, safer than full bypass
cxa() {
    command codex --approve-for-me "$@"
}

# -----------------------------------------------------------------------------
# Starship
# -----------------------------------------------------------------------------

# The system-wide /etc/zsh/zshrc (grml-zsh-config) activates its own prompt
# theme before this file loads. Its precmd hook (prompt_grml_precmd)
# reassigns $PROMPT on every single command, silently clobbering whatever
# starship sets up below - starship's own precmd hook only tracks command
# duration/status, it never re-assigns $PROMPT itself (it relies on nothing
# else touching it after init). `prompt off` removes grml's theme hooks via
# zsh's own prompt-theme API before starship installs its own.
prompt off

if (( $+commands[starship] )); then
    typeset -g ZLE_RPROMPT_INDENT=0
    eval "$(starship init zsh)"
fi


# -----------------------------------------------------------------------------
# Autosuggestions
# -----------------------------------------------------------------------------

if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi


# -----------------------------------------------------------------------------
# Syntax highlighting
# MUST stay last.
# -----------------------------------------------------------------------------

if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

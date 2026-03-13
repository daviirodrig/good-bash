#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════╗
# ║          🚀 good-bash — User-Local Bash Setup              ║
# ║                                                            ║
# ║  • No sudo required                                       ║
# ║  • Fully idempotent (safe to re-run)                      ║
# ║  • Everything in ~/.local                                  ║
# ║                                                            ║
# ║  curl -fsSL https://yourserver.com/good-bash.sh | bash     ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─────────────────────────── Paths ────────────────────────────
PREFIX="$HOME/.local"
BIN="$PREFIX/bin"
SHARE="$PREFIX/share"
BLESH_DIR="$SHARE/blesh"
BLESH_SRC="$SHARE/blesh-src"
CONFIG_DIR="$HOME/.config"
BASHRC="$HOME/.bashrc"
INPUTRC="$HOME/.inputrc"
TMP_DIR="$(mktemp -d)"

GOOD_BASH_MARKER="# >>> good-bash >>>"
GOOD_BASH_END="# <<< good-bash <<<"

# ─────────────────────────── Colors ───────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'  # Added this line
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─────────────────────────── Helpers ──────────────────────────
info()    { echo -e "${BLUE}${BOLD}[INFO]${RESET}    $*"; }
success() { echo -e "${GREEN}${BOLD}[✔]${RESET}      $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}    $*"; }
error()   { echo -e "${RED}${BOLD}[✘]${RESET}      $*"; }
step()    { echo -e "\n${PURPLE}${BOLD}━━━━━ $* ━━━━━${RESET}"; }

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# Download with progress bar
# Usage: download <url> <output_file>
download() {
    local url="$1" output="$2"
    curl -fSL --progress-bar "$url" -o "$output"
}

banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'

   ██████╗  ██████╗  ██████╗ ██████╗       ██████╗  █████╗ ███████╗██╗  ██╗
  ██╔════╝ ██╔═══██╗██╔═══██╗██╔══██╗      ██╔══██╗██╔══██╗██╔════╝██║  ██║
  ██║  ███╗██║   ██║██║   ██║██║  ██║█████╗██████╔╝███████║███████╗███████║
  ██║   ██║██║   ██║██║   ██║██║  ██║╚════╝██╔══██╗██╔══██║╚════██║██╔══██║
  ╚██████╔╝╚██████╔╝╚██████╔╝██████╔╝      ██████╔╝██║  ██║███████║██║  ██║
   ╚═════╝  ╚═════╝  ╚═════╝ ╚═════╝       ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

BANNER
    echo -e "${RESET}"
    echo -e "  ${DIM}No sudo. Idempotent. User-local. Beautiful.${RESET}\n"
}

# ──────────────────── Detect Architecture ─────────────────────
detect_arch() {
    ARCH="$(uname -m)"
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "$ARCH" in
        x86_64)        ARCH_ALT="amd64"; ARCH_RUST="x86_64" ;;
        aarch64|arm64) ARCH_ALT="arm64"; ARCH_RUST="aarch64" ;;
        armv7l)        ARCH_ALT="armhf"; ARCH_RUST="armv7" ;;
        *)             ARCH_ALT="$ARCH"; ARCH_RUST="$ARCH" ;;
    esac

    case "$OS" in
        linux)  OS_RUST="unknown-linux-musl"; OS_ALT="linux" ;;
        darwin) OS_RUST="apple-darwin"; OS_ALT="darwin" ;;
        *)      OS_RUST="$OS"; OS_ALT="$OS" ;;
    esac

    TRIPLE="${ARCH_RUST}-${OS_RUST}"
    info "Platform: ${BOLD}${OS}/${ARCH}${RESET} (${TRIPLE})"
}

ensure_dirs() {
    mkdir -p "$BIN" "$SHARE" "$CONFIG_DIR" "$TMP_DIR"
}

ensure_path() {
    if [[ ":$PATH:" != *":$BIN:"* ]]; then
        export PATH="$BIN:$PATH"
    fi
}

# Fetch latest GitHub release tag for a repo
# Usage: gh_latest_tag <owner/repo>
gh_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

# ──────────────────── Install: Starship ───────────────────────
install_starship() {
    step "Starship prompt"

    if command -v starship &>/dev/null; then
        success "Starship already installed ($(starship --version 2>/dev/null | head -1))"
        return
    fi

    info "Installing Starship to $BIN..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$BIN" 2>/dev/null

    if [[ -x "$BIN/starship" ]]; then
        success "Starship installed"
    else
        warn "Starship install failed"
    fi
}

# ──────────────────── Install: fzf ────────────────────────────
install_fzf() {
    step "fzf (fuzzy finder)"

    if command -v fzf &>/dev/null; then
        success "fzf already installed ($(fzf --version 2>/dev/null | awk '{print $1}'))"
        return
    fi

    local fzf_arch="$ARCH_ALT"
    [[ "$ARCH" == "x86_64" ]] && fzf_arch="amd64"
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && fzf_arch="arm64"

    local version
    version=$(gh_latest_tag "junegunn/fzf")
    version="${version#v}"

    if [[ -n "$version" ]]; then
        local url="https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-${OS_ALT}_${fzf_arch}.tar.gz"
        info "Downloading fzf $version..."
        download "$url" "$TMP_DIR/fzf.tar.gz"
        tar -xzf "$TMP_DIR/fzf.tar.gz" -C "$BIN"
        chmod +x "$BIN/fzf"
        success "fzf installed"
    else
        warn "Could not install fzf"
    fi
}

# ──────────────────── Install: ble.sh ─────────────────────────
install_blesh() {
    step "ble.sh (autosuggestions + syntax highlighting)"

    if [[ -f "$BLESH_DIR/ble.sh" ]]; then
        success "ble.sh already installed"
        return
    fi

    if ! command -v make &>/dev/null; then
        warn "'make' not found — cannot build ble.sh"
        warn "Ask your admin to install: make gawk"
        return 1
    fi

    info "Cloning ble.sh (this takes ~30s)..."
    git clone --recursive --depth 1 --shallow-submodules \
        https://github.com/akinomyoga/ble.sh.git "$TMP_DIR/ble.sh" 2>/dev/null

    info "Building ble.sh..."
    make -C "$TMP_DIR/ble.sh" install PREFIX="$PREFIX" 2>/dev/null

    rm -rf "$BLESH_SRC"
    mv "$TMP_DIR/ble.sh" "$BLESH_SRC"

    if [[ -f "$BLESH_DIR/ble.sh" ]]; then
        success "ble.sh installed"
    else
        warn "ble.sh build may have failed"
    fi
}

# ──────────────────── Install: eza ────────────────────────────
install_eza() {
    if command -v eza &>/dev/null; then
        success "eza already installed"
        return
    fi

    local eza_arch="$ARCH"
    [[ "$ARCH" == "arm64" ]] && eza_arch="aarch64"

    local version
    version=$(gh_latest_tag "eza-community/eza")
    version="${version#v}"

    if [[ -z "$version" ]]; then warn "Could not fetch eza version"; return; fi

    local url
    if [[ "$OS" == "linux" ]]; then
        url="https://github.com/eza-community/eza/releases/download/v${version}/eza_${eza_arch}-unknown-linux-musl.tar.gz"
    elif [[ "$OS" == "darwin" ]]; then
        url="https://github.com/eza-community/eza/releases/download/v${version}/eza_${eza_arch}-apple-darwin.tar.gz"
    else
        warn "eza: unsupported OS"; return
    fi

    info "Downloading eza $version..."
    download "$url" "$TMP_DIR/eza.tar.gz" && \
    tar -xzf "$TMP_DIR/eza.tar.gz" -C "$TMP_DIR" && \
    mv "$TMP_DIR/eza" "$BIN/eza" && \
    chmod +x "$BIN/eza" && \
    success "eza installed" || warn "eza install failed"
}

# ──────────────────── Install: bat ────────────────────────────
install_bat() {
    if command -v bat &>/dev/null || command -v batcat &>/dev/null; then
        success "bat already installed"
        return
    fi

    local bat_arch="$ARCH"
    [[ "$ARCH" == "arm64" ]] && bat_arch="aarch64"
    local bat_triple
    [[ "$OS" == "linux" ]] && bat_triple="${bat_arch}-unknown-linux-musl"
    [[ "$OS" == "darwin" ]] && bat_triple="${bat_arch}-apple-darwin"

    local version
    version=$(gh_latest_tag "sharkdp/bat")
    version="${version#v}"

    if [[ -z "$version" ]]; then warn "Could not fetch bat version"; return; fi

    local name="bat-v${version}-${bat_triple}"
    local url="https://github.com/sharkdp/bat/releases/download/v${version}/${name}.tar.gz"
    info "Downloading bat $version..."
    download "$url" "$TMP_DIR/bat.tar.gz" && \
    tar -xzf "$TMP_DIR/bat.tar.gz" -C "$TMP_DIR" && \
    mv "$TMP_DIR/${name}/bat" "$BIN/bat" && \
    chmod +x "$BIN/bat" && \
    success "bat installed" || warn "bat install failed"
}

# ──────────────────── Install: fd ─────────────────────────────
install_fd() {
    if command -v fd &>/dev/null || command -v fdfind &>/dev/null; then
        success "fd already installed"
        return
    fi

    local fd_arch="$ARCH"
    [[ "$ARCH" == "arm64" ]] && fd_arch="aarch64"
    local fd_triple
    [[ "$OS" == "linux" ]] && fd_triple="${fd_arch}-unknown-linux-musl"
    [[ "$OS" == "darwin" ]] && fd_triple="${fd_arch}-apple-darwin"

    local version
    version=$(gh_latest_tag "sharkdp/fd")
    version="${version#v}"

    if [[ -z "$version" ]]; then warn "Could not fetch fd version"; return; fi

    local name="fd-v${version}-${fd_triple}"
    local url="https://github.com/sharkdp/fd/releases/download/v${version}/${name}.tar.gz"
    info "Downloading fd $version..."
    download "$url" "$TMP_DIR/fd.tar.gz" && \
    tar -xzf "$TMP_DIR/fd.tar.gz" -C "$TMP_DIR" && \
    mv "$TMP_DIR/${name}/fd" "$BIN/fd" && \
    chmod +x "$BIN/fd" && \
    success "fd installed" || warn "fd install failed"
}

# ──────────────────── Install: ripgrep ────────────────────────
install_ripgrep() {
    if command -v rg &>/dev/null; then
        success "ripgrep already installed"
        return
    fi

    local rg_arch="$ARCH"
    [[ "$ARCH" == "arm64" ]] && rg_arch="aarch64"
    local rg_triple
    [[ "$OS" == "linux" ]] && rg_triple="${rg_arch}-unknown-linux-musl"
    [[ "$OS" == "darwin" ]] && rg_triple="${rg_arch}-apple-darwin"

    local version
    version=$(gh_latest_tag "BurntSushi/ripgrep")

    if [[ -z "$version" ]]; then warn "Could not fetch ripgrep version"; return; fi

    local name="ripgrep-${version}-${rg_triple}"
    local url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/${name}.tar.gz"
    info "Downloading ripgrep $version..."
    download "$url" "$TMP_DIR/rg.tar.gz" && \
    tar -xzf "$TMP_DIR/rg.tar.gz" -C "$TMP_DIR" && \
    mv "$TMP_DIR/${name}/rg" "$BIN/rg" && \
    chmod +x "$BIN/rg" && \
    success "ripgrep installed" || warn "ripgrep install failed"
}

# ──────────────────── Install: zoxide ─────────────────────────
install_zoxide() {
    if command -v zoxide &>/dev/null; then
        success "zoxide already installed"
        return
    fi

    info "Installing zoxide..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | \
        sh -s -- --bin-dir "$BIN" 2>/dev/null

    if [[ -x "$BIN/zoxide" ]]; then
        success "zoxide installed"
    else
        warn "zoxide install failed"
    fi
}

# ──────────────────── Install: btop ───────────────────────────
install_btop() {
    if command -v btop &>/dev/null; then
        success "btop already installed"
        return
    fi

    if [[ "$OS" != "linux" ]]; then
        warn "btop: no static binary for $OS — skipping"
        return
    fi

    local btop_arch
    case "$ARCH" in
        x86_64)  btop_arch="x86_64" ;;
        aarch64) btop_arch="aarch64" ;;
        *)       warn "btop: unsupported arch $ARCH"; return ;;
    esac

    local version
    version=$(gh_latest_tag "aristocratos/btop")
    version="${version#v}"

    if [[ -z "$version" ]]; then warn "Could not fetch btop version"; return; fi

    local url="https://github.com/aristocratos/btop/releases/download/v${version}/btop-${btop_arch}-linux-musl.tbz"
    info "Downloading btop $version..."
    download "$url" "$TMP_DIR/btop.tbz" && \
    tar -xjf "$TMP_DIR/btop.tbz" -C "$TMP_DIR" && \
    cp "$TMP_DIR/btop/bin/btop" "$BIN/btop" && \
    chmod +x "$BIN/btop" && \
    success "btop installed" || warn "btop install failed"
}

# ──────────────────── Install: All modern tools ───────────────
install_modern_tools() {
    step "Modern CLI tools (all user-local to ~/.local/bin)"

    install_eza
    install_bat
    install_fd
    install_ripgrep
    install_zoxide
    install_btop
}

# ──────────────────── Configure: ble.sh ───────────────────────
configure_blesh() {
    step "Configuring ble.sh"

    mkdir -p "$HOME/.config/blesh"

    cat > "$HOME/.config/blesh/init.sh" << 'BLESH_CONFIG'
# ─── good-bash ble.sh configuration ───

ble-face -s argument_error          fg=red,bold
ble-face -s auto_complete           fg=238
ble-face -s command_alias           fg=teal
ble-face -s command_builtin         fg=yellow
ble-face -s command_directory       fg=blue,underline
ble-face -s command_file            fg=green
ble-face -s command_function        fg=purple
ble-face -s command_keyword         fg=blue,bold
ble-face -s filename_directory      fg=blue,underline
ble-face -s filename_executable     fg=green,bold
ble-face -s filename_link           fg=cyan,underline
ble-face -s filename_orphan         fg=red,underline
ble-face -s region                  fg=white,bg=60
ble-face -s syntax_comment          fg=242,italic
ble-face -s syntax_error            fg=red,bg=52
ble-face -s syntax_glob             fg=magenta,bold
ble-face -s syntax_quoted           fg=green
ble-face -s syntax_varname          fg=208
ble-face -s varname_export          fg=208,bold

bleopt complete_auto_delay=100
bleopt complete_auto_complete=1
bleopt complete_auto_history=1
bleopt complete_menu_style=dense-nowrap
bleopt complete_menu_maxlines=20
bleopt highlight_syntax=1
bleopt highlight_filename=1
bleopt complete_ambiguous=1
bleopt complete_menu_complete=1

ble-bind -f right       auto_complete/insert
ble-bind -f end         auto_complete/insert
ble-bind -f C-right     auto_complete/insert-word
ble-bind -f 'C-?'       kill-backward-cword

BLESH_CONFIG

    success "ble.sh configured"
}

# ──────────────────── Configure: Starship ─────────────────────
configure_starship() {
    step "Configuring Starship"

    cat > "$CONFIG_DIR/starship.toml" << 'STARSHIP_CONFIG'
# good-bash starship config
# Format: # user @ hostname in ~/path on git:branch x [HH:MM:SS] C:code

format = """
[#](bold blue) \
$username\
[@](white)\
$hostname\
[in](white) \
$directory\
$git_branch\
$git_status\
$status\
$time\
$line_break\
[\\$](white) """

add_newline = false
command_timeout = 1000

[username]
style_user = "bold bright-blue"
style_root = "bold red"
format = "[$user]($style)"
show_always = true

[hostname]
ssh_only = false
format = "[$hostname]($style) "
style = "bold green"
disabled = false

[directory]
style = "bold 208"
format = "[$path]($style) "
truncation_length = 5
truncation_symbol = "…/"
truncate_to_repo = false

[git_branch]
symbol = ""
style = "bold bright-blue"
format = "[on](white) [git:](bold blue)[$branch]($style) "

[git_status]
format = '([$all_status$ahead_behind]($style) )'
style = "bold red"
conflicted = "x"
ahead = ">"
behind = "<"
diverged = "<>"
untracked = "?"
stashed = "$"
modified = "x"
staged = "+"
renamed = "r"
deleted = "-"

[status]
disabled = false
format = "[C:$status]($style) "
style = "bold red"
# Only shown when exit code != 0

[time]
disabled = false
format = "[\\[$time\\]](white) "
time_format = "%H:%M:%S"

[character]
disabled = true

# Disable everything we don't use
[aws]
disabled = true
[gcloud]
disabled = true
[package]
disabled = true
[nodejs]
disabled = true
[python]
disabled = true
[rust]
disabled = true
[golang]
disabled = true
[docker_context]
disabled = true
[kubernetes]
disabled = true
[os]
disabled = true
[cmd_duration]
disabled = true
[jobs]
disabled = true

STARSHIP_CONFIG

    success "Starship configured"
}

# ──────────────────── Configure: inputrc ──────────────────────
configure_inputrc() {
    step "Configuring ~/.inputrc"

    cat > "$INPUTRC" << 'INPUTRC_CONTENT'
# ─── good-bash inputrc ───
$include /etc/inputrc

set completion-ignore-case on
set completion-map-case on
set show-all-if-ambiguous on
set show-all-if-unmodified on
set colored-stats on
set colored-completion-prefix on
set visible-stats on
set mark-symlinked-directories on
set bell-style none
set enable-bracketed-paste on

# Up/Down: search history by prefix
"\e[A": history-search-backward
"\e[B": history-search-forward

# Ctrl+Left/Right: move by word
"\e[1;5C": forward-word
"\e[1;5D": backward-word

# Ctrl+Backspace: delete word
"\C-H": backward-kill-word

# Tab cycles through completions
TAB: menu-complete
"\e[Z": menu-complete-backward

INPUTRC_CONTENT

    success "inputrc configured"
}

# ──────────────────── Configure: .bashrc ──────────────────────
configure_bashrc() {
    step "Configuring ~/.bashrc"

    # Backup only on first run
    if [[ -f "$BASHRC" ]] && ! grep -q "$GOOD_BASH_MARKER" "$BASHRC" 2>/dev/null; then
        local backup="$BASHRC.pre-good-bash.$(date +%Y%m%d%H%M%S)"
        cp "$BASHRC" "$backup"
        success "First run — backed up .bashrc to $(basename "$backup")"
    fi

    # Remove previous block (idempotent)
    if [[ -f "$BASHRC" ]] && grep -q "$GOOD_BASH_MARKER" "$BASHRC" 2>/dev/null; then
        awk "/$GOOD_BASH_MARKER/{skip=1} /$GOOD_BASH_END/{skip=0; next} !skip" \
            "$BASHRC" > "$TMP_DIR/bashrc_clean"
        mv "$TMP_DIR/bashrc_clean" "$BASHRC"
        info "Replaced existing good-bash block"
    fi

    touch "$BASHRC"

    cat >> "$BASHRC" << 'BASHRC_BLOCK'
# >>> good-bash >>>
# ╔══════════════════════════════════════════════════════════════╗
# ║  Managed by good-bash — re-run installer to update         ║
# ║  Do not edit between the >>> and <<< markers               ║
# ╚══════════════════════════════════════════════════════════════╝

# ─── PATH ───
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && \
    export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/bin" ]] && [[ ":$PATH:" != *":$HOME/bin:"* ]] && \
    export PATH="$HOME/bin:$PATH"

# ─── ble.sh (MUST be near top) ───
[[ $- == *i* ]] && [[ -f "$HOME/.local/share/blesh/ble.sh" ]] && \
    source "$HOME/.local/share/blesh/ble.sh" --noattach

# ─── History ───
HISTSIZE=500000
HISTFILESIZE=1000000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T  "
HISTIGNORE="ls:ll:la:cd:pwd:exit:clear:history"
shopt -s histappend
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"

# ─── Shell Options ───
shopt -s autocd 2>/dev/null
shopt -s cdspell 2>/dev/null
shopt -s dirspell 2>/dev/null
shopt -s globstar 2>/dev/null
shopt -s nocaseglob 2>/dev/null
shopt -s checkwinsize 2>/dev/null
shopt -s no_empty_cmd_completion 2>/dev/null
shopt -s cmdhist 2>/dev/null
shopt -s lithist 2>/dev/null

# ─── Bash Completion ───
for _bc in /usr/share/bash-completion/bash_completion \
           /etc/bash_completion \
           /opt/homebrew/etc/profile.d/bash_completion.sh \
           /usr/local/etc/profile.d/bash_completion.sh; do
    [[ -r "$_bc" ]] && source "$_bc" && break
done
unset _bc

# ─── fzf ───
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash 2>/dev/null)" || {
        [[ -f /usr/share/fzf/key-bindings.bash ]] && source /usr/share/fzf/key-bindings.bash
        [[ -f /usr/share/fzf/completion.bash ]]   && source /usr/share/fzf/completion.bash
        [[ -f ~/.fzf.bash ]]                       && source ~/.fzf.bash
    }

    # fzf theme (Catppuccin Mocha)
    export FZF_DEFAULT_OPTS="
        --height=60% --layout=reverse --border=rounded
        --info=inline --margin=1 --padding=1
        --prompt='> ' --pointer='▶' --marker='✓'
        --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
        --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
        --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

    _fzf_bat="bat"
    command -v bat &>/dev/null || { command -v batcat &>/dev/null && _fzf_bat="batcat"; }
    export FZF_CTRL_T_OPTS="--preview '${_fzf_bat} --color=always --line-range :500 {} 2>/dev/null || cat {} 2>/dev/null'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always --level=2 {} 2>/dev/null || ls -la {}'"
    unset _fzf_bat
fi

# ─── Zoxide ───
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# ─── Starship ───
command -v starship &>/dev/null && eval "$(starship init bash)"

# ─── Aliases: ls ───
if command -v eza &>/dev/null; then
    alias ls='eza --color=always --group-directories-first'
    alias ll='eza --color=always --group-directories-first -la'
    alias la='eza --color=always --group-directories-first -a'
    alias lt='eza --color=always --group-directories-first --tree --level=2'
    alias l='eza --color=always --group-directories-first -l'
else
    alias ls='ls --color=auto 2>/dev/null || ls -G'
    alias ll='ls -la'
    alias la='ls -a'
fi

# ─── Aliases: modern tools ───
command -v bat    &>/dev/null && alias cat='bat --paging=never'
command -v batcat &>/dev/null && ! command -v bat &>/dev/null && alias cat='batcat --paging=never'
command -v rg     &>/dev/null && alias grep='rg'
command -v btop   &>/dev/null && alias top='btop'

# ─── Aliases: navigation ───
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -pv'
alias path='echo -e ${PATH//:/\\n}'
alias reload='source ~/.bashrc'
alias edit-bash='${EDITOR:-nano} ~/.bashrc'
alias cls='clear'

# ─── Aliases: git ───
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# ─── Functions ───
mkcd() { mkdir -p "$@" && cd "$_"; }

extract() {
    if [[ ! -f "$1" ]]; then echo "'$1' is not a valid file"; return 1; fi
    case "$1" in
        *.tar.bz2) tar xjf "$1"    ;; *.tar.gz)  tar xzf "$1"   ;;
        *.tar.xz)  tar xJf "$1"    ;; *.bz2)     bunzip2 "$1"   ;;
        *.gz)       gunzip "$1"     ;; *.tar)     tar xf "$1"    ;;
        *.tbz2)     tar xjf "$1"    ;; *.tgz)     tar xzf "$1"   ;;
        *.zip)      unzip "$1"      ;; *.Z)       uncompress "$1" ;;
        *.7z)       7z x "$1"       ;; *.rar)     unrar x "$1"   ;;
        *)          echo "Cannot extract '$1'" ;;
    esac
}

serve() { python3 -m http.server "${1:-8000}"; }
weather() { curl -s "wttr.in/${1:-}"; }
cheat() { curl -s "cheat.sh/$1"; }

# ─── Environment ───
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"
export LANG="${LANG:-en_US.UTF-8}"
export LESS="-R --mouse"

if command -v bat &>/dev/null; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
elif command -v batcat &>/dev/null; then
    export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
fi

# ─── ble.sh attach (MUST be last) ───
[[ ${BLE_VERSION-} ]] && ble-attach
# <<< good-bash <<<
BASHRC_BLOCK

    success ".bashrc configured"
}

# ──────────────────── Uninstall ───────────────────────────────
uninstall() {
    banner
    echo -e "${RED}${BOLD}Uninstalling good-bash...${RESET}\n"

    if [[ -f "$BASHRC" ]] && grep -q "$GOOD_BASH_MARKER" "$BASHRC" 2>/dev/null; then
        awk "/$GOOD_BASH_MARKER/{skip=1} /$GOOD_BASH_END/{skip=0; next} !skip" \
            "$BASHRC" > "$TMP_DIR/bashrc_clean"
        mv "$TMP_DIR/bashrc_clean" "$BASHRC"
        success "Removed good-bash block from .bashrc"
    fi

    rm -f "$HOME/.config/blesh/init.sh"
    rm -f "$INPUTRC"
    success "Removed inputrc and ble.sh config"

    echo ""
    info "Binaries NOT removed (delete manually if desired):"
    echo -e "  ${DIM}rm -rf ~/.local/share/blesh* ~/.local/bin/{starship,fzf,eza,bat,fd,rg,zoxide,btop}${RESET}"
    echo -e "  ${DIM}rm -f ~/.config/starship.toml${RESET}"
    echo ""
    success "Done. Restart your shell."
    exit 0
}

# ──────────────────── Summary ─────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}"
    cat << 'DONE'
  ╔══════════════════════════════════════════════════════════════╗
  ║              ✨ good-bash setup complete! ✨               ║
  ╚══════════════════════════════════════════════════════════════╝
DONE
    echo -e "${RESET}"

    echo -e "${BOLD}Installed (all in ~/.local):${RESET}"
    local tools=(starship fzf eza bat fd rg zoxide btop)
    for t in "${tools[@]}"; do
        if command -v "$t" &>/dev/null; then
            echo -e "  ${GREEN}✔${RESET} $t"
        else
            echo -e "  ${DIM}✗ $t (not available)${RESET}"
        fi
    done
    [[ -f "$BLESH_DIR/ble.sh" ]] && echo -e "  ${GREEN}✔${RESET} ble.sh" || echo -e "  ${DIM}✗ ble.sh${RESET}"

    echo ""
    echo -e "${BOLD}Your prompt will look like:${RESET}"
    echo -e "  ${BLUE}#${RESET} ${CYAN}user${RESET}${WHITE}@${RESET}${GREEN}hostname${RESET} ${WHITE}in${RESET} \033[38;5;208m~/some/path${RESET} ${WHITE}on${RESET} ${BLUE}git:${RESET}${CYAN}main${RESET} ${RED}x${RESET} ${WHITE}[19:37:56]${RESET} ${RED}C:1${RESET}"
    echo -e "  \$ _"

    echo ""
    echo -e "${BOLD}Keyboard shortcuts:${RESET}"
    echo -e "  ${CYAN}Ctrl+R${RESET}       Fuzzy search history"
    echo -e "  ${CYAN}Ctrl+T${RESET}       Fuzzy find files"
    echo -e "  ${CYAN}Alt+C${RESET}        Fuzzy cd into directory"
    echo -e "  ${CYAN}→ / End${RESET}      Accept autosuggestion"
    echo -e "  ${CYAN}Ctrl+→${RESET}       Accept next word"
    echo -e "  ${CYAN}↑ / ↓${RESET}        Search history by prefix"
    echo -e "  ${CYAN}Tab${RESET}          Cycle through completions"

    echo ""
    echo -e "${BOLD}Useful:${RESET}"
    echo -e "  ${CYAN}mkcd dir${RESET}     Create + cd"
    echo -e "  ${CYAN}extract f${RESET}    Extract any archive"
    echo -e "  ${CYAN}weather${RESET}      Weather report"
    echo -e "  ${CYAN}cheat cmd${RESET}    Cheat sheet"
    echo -e "  ${CYAN}z dir${RESET}        Smart cd (learns your habits)"

    echo ""
    echo -e "${YELLOW}${BOLD}Next:${RESET} Run ${CYAN}source ~/.bashrc${RESET} or open a new terminal"
    echo ""
}

# ──────────────────────── Main ────────────────────────────────
main() {
    case "${1:-}" in
        --uninstall|-u) uninstall ;;
        --help|-h)
            echo "Usage: good-bash.sh [OPTIONS]"
            echo ""
            echo "  (no args)       Install/update everything"
            echo "  --minimal, -m   Skip modern CLI tools"
            echo "  --uninstall, -u Remove good-bash config"
            echo "  --help, -h      Show this help"
            exit 0
            ;;
    esac

    banner
    detect_arch
    ensure_dirs
    ensure_path

    if ! command -v git &>/dev/null; then
        error "git is required but not found. Ask your admin to install it."
        exit 1
    fi
    if ! command -v curl &>/dev/null; then
        error "curl is required but not found. Ask your admin to install it."
        exit 1
    fi

    install_starship
    install_fzf
    install_blesh

    if [[ "${1:-}" != "--minimal" ]] && [[ "${1:-}" != "-m" ]]; then
        install_modern_tools
    fi

    configure_blesh
    configure_starship
    configure_inputrc
    configure_bashrc

    print_summary
}

main "$@"

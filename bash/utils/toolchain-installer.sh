#!/usr/bin/env bash
# Requires Bash 5.2+
set -euo pipefail

# ANSI color codes
readonly CLR_RESET=$'\e[0m'
readonly CLR_BOLD=$'\e[1m'
readonly CLR_CYAN=$'\e[36m'
readonly CLR_GREEN=$'\e[32m'
readonly CLR_YELLOW=$'\e[33m'
readonly CLR_RED=$'\e[31m'

# Ensure core user binary paths are visible during execution
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.local/share/fnm:${HOME}/.gvm/bin:${PATH}"

log_info()    { printf "${CLR_CYAN}[INFO]${CLR_RESET} %s\n" "$*"; }
log_success() { printf "${CLR_GREEN}[OK]${CLR_RESET} %s\n" "$*"; }
log_warn()    { printf "${CLR_YELLOW}[WARN]${CLR_RESET} %s\n" "$*"; }
log_error()   { printf "${CLR_RED}[ERROR]${CLR_RESET} %s\n" "$*" >&2; }

# Check baseline prerequisites
for dep in curl tar; do
    if ! command -v "$dep" &> /dev/null; then
        log_error "Missing required core utility: $dep"
        exit 1
    fi
done

# Toolchain definitions: title|binary_to_check|install_command
declare -A TOOLS=(
    [rustup]="Rust Toolchain (rustup)|rustup|curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
    [uv]="uv (Python package installer)|uv|curl -LsSf https://astral.sh/uv/install.sh | sh"
    [fnm]="fnm (Fast Node Manager)|fnm|curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell"
    [pnpm]="pnpm Package Manager|pnpm|curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME=\"$HOME/.local/share/pnpm\" sh -"
    [mise]="mise-en-place dev environment|mise|curl https://mise.run | sh"
    [deno]="Deno Runtime|deno|curl -fsSL https://deno.land/install.sh | sh"
    [gvm]="Go Version Manager (gvm)|gvm|curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer | bash"
    [docker]="Docker Engine|docker|curl -fsSL https://get.docker.com | sh"
    [agy]="Google Antigravity CLI|agy|curl -fsSL https://antigravity.google/install.sh | bash"
)

# Deterministic order for menus
ORDERED_KEYS=(rustup uv fnm pnpm mise deno gvm docker agy)

install_tool() {
    local key="$1"
    if [[ -z "${TOOLS[$key]:-}" ]]; then
        log_error "Unknown toolchain: $key"
        return 1
    fi

    IFS='|' read -r name bin_check cmd <<< "${TOOLS[$key]}"

    # GVM stores its entrypoint as a shell function in ~/.gvm/scripts/gvm rather than a standard binary
    if [[ "$key" == "gvm" && -d "${HOME}/.gvm" ]] || command -v "$bin_check" &> /dev/null; then
        log_warn "$name ($bin_check) is already installed. Skipping."
        return 0
    fi

    log_info "Installing $name..."
    if eval "$cmd"; then
        log_success "$name installed successfully."
        # Source fnm or local bins directly if needed downstream
        if [[ "$key" == "fnm" ]] && command -v fnm &> /dev/null; then
            eval "$(fnm env)"
            fnm install --lts || true
        fi
    else
        log_error "Failed to install $name."
        return 1
    fi
}

run_interactive() {
    printf "%sModern Linux Toolchain Installer%s\n\n" "$CLR_BOLD" "$CLR_RESET"
    
    local menu_items=()
    for key in "${ORDERED_KEYS[@]}"; do
        IFS='|' read -r name _ _ <<< "${TOOLS[$key]}"
        menu_items+=("$name ($key)")
    done
    menu_items+=("All Toolchains" "Quit")

    PS3=$'\nSelect a toolchain to install: '
    select opt in "${menu_items[@]}"; do
        if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#ORDERED_KEYS[@]}" ]]; then
            local selected_key="${ORDERED_KEYS[$((REPLY-1))]}"
            install_tool "$selected_key"
        elif [[ "$opt" == "All Toolchains" ]]; then
            for key in "${ORDERED_KEYS[@]}"; do
                install_tool "$key"
            done
            break
        elif [[ "$opt" == "Quit" ]]; then
            log_info "Exiting."
            break
        else
            log_warn "Invalid option: $REPLY"
        fi
    done
}

# --- Entrypoint ---
if [[ $# -eq 0 ]]; then
    run_interactive
else
    for arg in "$@"; do
        if [[ "$arg" == "--all" || "$arg" == "-a" ]]; then
            for key in "${ORDERED_KEYS[@]}"; do
                install_tool "$key"
            done
        else
            install_tool "$arg"
        fi
    done
fi

#!/usr/bin/env bash

set -euo pipefail

# --- INSTALL ACTIONS ---

install_pnpm() {
    if ! command -v pnpm &> /dev/null; then
        echo "Installing pnpm..."
        curl -fsSL https://get.pnpm.io/install.sh | sh -
    else
        echo "pnpm is already installed."
    fi
}

install_rustup() {
    if ! command -v rustup &> /dev/null; then
        echo "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    else
        echo "Rustup is already installed."
    fi
}

install_uv() {
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    else
        echo "uv is already installed."
    fi
}

install_deno() {
    if ! command -v deno &> /dev/null; then
        echo "Installing Deno..."
        curl -fsSL https://deno.land/x/install/install.sh | sh
    else
        echo "Deno is already installed."
    fi
}

install_gvm() {
    if [ ! -d "$HOME/.gvm" ]; then
        echo "Installing GVM (Go Version Manager)..."
        # Requires curl, git, and make as basic prerequisites
        curl -sL https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer | bash
    else
        echo "GVM is already installed."
    fi
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
    else
        echo "Docker is already installed."
    fi
}

install_pacstall() {
    echo "Script is not working, install by hand"
    if ! command -v pacstall &> /dev/null; then
        echo "Installing pacstall..."
        sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)"
    else
        echo "Pacstall is already installed."
    fi
}

# --- INTERACTIVE MENU ---

options=(
    "pnpm"
    "Rust (rustup)"
    "uv"
    "Deno"
    "GVM"
    "Docker"
    "Pacstall"
    "Install All"
    "Quit"
)

echo "Select a toolchain to install:"
select opt in "${options[@]}"; do
    case "$opt" in
        "pnpm")          install_pnpm ;;
        "Rust (rustup)") install_rustup ;;
        "uv")            install_uv ;;
        "Deno")          install_deno ;;
        "GVM")           install_gvm ;;
        "Docker")        install_docker ;;
        "Pacstall")          install_pacstall ;;
        "Install All")
            install_pnpm
            install_rustup
            install_uv
            install_deno
            install_gvm
            install_docker
            install_pacstall
            ;;
        "Quit")
            echo "Exiting."
            break
            ;;
        *) 
            echo "Invalid option $REPLY"
            ;;
    esac
done

#!/usr/bin/env bash
#
# Arcium One‑Click Environment Installer
# Installs: Rust, Node.js (LTS via nvm), Docker, Solana CLI (devnet), Arcium CLI
# Platforms: macOS, Linux (Debian/Ubuntu, Fedora)
# Style: clean, predictable, reproducible — safe to re‑run.
#
# © 2025. MIT License.
#
set -euo pipefail

# ========== Pretty Output ==========
BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
GREEN="\033[32m"; CYAN="\033[36m"; YELLOW="\033[33m"; RED="\033[31m"
CHECK="${GREEN}✔${RESET}"; CROSS="${RED}✖${RESET}"; INFO="${CYAN}➜${RESET}"

line() { printf "${DIM}%s${RESET}\n" "────────────────────────────────────────────────────────────"; }
title() {
  line
  printf "${BOLD}Arcium Environment Setup${RESET}\n"
  printf "${DIM}macOS & Linux · Rust • Node • Docker • Solana • Arcium${RESET}\n"
  line
}
log()    { printf "%b %s\n" "$INFO" "$1"; }
ok()     { printf "%b %s\n" "$CHECK" "$1"; }
warn()   { printf "%b %s\n" "$YELLOW!${RESET}" "$1"; }
fail()   { printf "%b %s\n" "$CROSS" "$1"; exit 1; }

# ========== OS / Shell Detection ==========
OS="$(uname -s || true)"
IS_DARWIN=0; IS_LINUX=0
case "$OS" in
  Darwin) IS_DARWIN=1 ;;
  Linux)  IS_LINUX=1  ;;
  *) fail "Unsupported OS: $OS";;
esac

# package manager hints for Linux
HAVE_APT=0; HAVE_DNF=0
if [ "$IS_LINUX" -eq 1 ]; then
  command -v apt-get >/dev/null 2>&1 && HAVE_APT=1
  command -v dnf >/dev/null 2>&1 && HAVE_DNF=1
fi

# Determine user shell profile to modify PATH lines
detect_profile() {
  # Prefer interactive shell rc if present
  if [ -n "${ZDOTDIR:-}" ] && [ -f "$ZDOTDIR/.zshrc" ]; then echo "$ZDOTDIR/.zshrc"; return; fi
  if [ -f "$HOME/.zshrc" ]; then echo "$HOME/.zshrc"; return; fi
  if [ -f "$HOME/.bashrc" ]; then echo "$HOME/.bashrc"; return; fi
  if [ -f "$HOME/.bash_profile" ]; then echo "$HOME/.bash_profile"; return; fi
  echo "$HOME/.profile"
}
PROFILE_FILE="$(detect_profile)"

append_once() {
  local LINE="$1"
  local FILE="$2"
  grep -Fqs "$LINE" "$FILE" 2>/dev/null || printf "\n%s\n" "$LINE" >> "$FILE"
}

require_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      fail "This step requires root privileges and 'sudo' is not available."
    fi
    sudo -v || fail "Sudo authentication failed."
  fi
}

# ========== Installers ==========

install_rust() {
  if command -v rustc >/dev/null 2>&1; then
    ok "Rust already installed: $(rustc --version | awk '{print $2}')"
    return
  fi
  log "Installing Rust via rustup…"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shell env
  if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.cargo/env"
  fi
  append_once 'export PATH="$HOME/.cargo/bin:$PATH"' "$PROFILE_FILE"
  ok "Rust installed."
}

install_nvm_node_lts() {
  # nvm env bootstrap (if previously installed)
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.nvm/nvm.sh"
  fi

  if ! command -v nvm >/dev/null 2>&1; then
    log "Installing nvm (Node Version Manager)…"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck source=/dev/null
    . "$HOME/.nvm/nvm.sh"
    append_once 'export NVM_DIR="$HOME/.nvm"' "$PROFILE_FILE"
    append_once '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$PROFILE_FILE"
  fi

  if command -v node >/dev/null 2>&1; then
    ok "Node.js already installed: $(node --version)"
  else
    log "Installing Node.js LTS via nvm…"
    nvm install --lts
    nvm alias default 'lts/*'
    ok "Node.js installed: $(node --version)"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version | sed 's/Docker //')"
    return
  fi

  if [ "$IS_DARWIN" -eq 1 ]; then
    log "Installing Docker Desktop via Homebrew (requires Homebrew)…"
    if ! command -v brew >/dev/null 2>&1; then
      log "Homebrew not found. Installing Homebrew…"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # brew path for Apple Silicon/Intel
      if [ -d "/opt/homebrew/bin" ]; then
        append_once 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$PROFILE_FILE"
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      if [ -d "/usr/local/bin" ]; then
        append_once 'eval "$(/usr/local/bin/brew shellenv)"' "$PROFILE_FILE"
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
    brew install --cask docker
    ok "Docker Desktop installed. Please launch it once to finish setup."
    return
  fi

  if [ "$IS_LINUX" -eq 1 ]; then
    if [ "$HAVE_APT" -eq 1 ]; then
      require_sudo
      log "Installing Docker Engine (apt)…"
      sudo apt-get update -y
      sudo apt-get install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      # Try Ubuntu codename; fallback to Debian
      UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-}")"
      if [ -n "$UBUNTU_CODENAME" ]; then
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      else
        DEB_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")"
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $DEB_CODENAME stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      fi
      sudo apt-get update -y
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      sudo systemctl enable --now docker
      if command -v getent >/dev/null 2>&1 && getent group docker >/dev/null 2>&1; then
        : # group exists
      else
        require_sudo
        sudo groupadd docker || true
      fi
      require_sudo
      sudo usermod -aG docker "$USER" || true
      ok "Docker installed. You may need to log out/in for docker group to take effect."
      return
    fi

    if [ "$HAVE_DNF" -eq 1 ]; then
      require_sudo
      log "Installing Docker Engine (dnf)…"
      sudo dnf -y install dnf-plugins-core
      sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      sudo systemctl enable --now docker
      sudo usermod -aG docker "$USER" || true
      ok "Docker installed. You may need to log out/in for docker group to take effect."
      return
    fi

    fail "Unsupported Linux distro (no apt/dnf). Install Docker manually: https://docs.docker.com/engine/install/"
  fi
}

install_solana() {
  if command -v solana >/dev/null 2>&1; then
    ok "Solana CLI already installed: $(solana --version)"
  else
    log "Installing Solana CLI…"
    curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash -s -- -y
    append_once 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' "$PROFILE_FILE"
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    ok "Solana CLI installed."
  fi

  # Configure devnet
  if solana config set --url devnet >/dev/null 2>&1; then
    ok "Solana set to devnet."
  else
    warn "Could not set Solana config to devnet automatically."
  fi
}

install_arcium_cli() {
  if command -v arcium >/dev/null 2>&1; then
    ok "Arcium CLI already installed: $(arcium --version || echo 'detected')"
    return
  fi
  log "Installing Arcium CLI…"
  # Using provided installer endpoint
  curl --proto '=https' --tlsv1.2 -sSfL https://arcium-install.arcium.workers.dev/ | bash
  if command -v arcium >/dev/null 2>&1; then
    ok "Arcium CLI installed."
  else
    warn "Arcium CLI not found on PATH after install. Ensure installer updated your PATH."
  fi
}

verify_all() {
  line
  printf "${BOLD}Verification${RESET}\n"
  set +e
  printf "%-22s " "rustc ≥ 1.88.0";        rustc --version 2>/dev/null | awk '{print $2}' | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "cargo ≥ 1.88.0";        cargo --version 2>/dev/null | awk '{print $2}' | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "node ≥ 18 (LTS)";       node --version 2>/dev/null | sed 's/v//' | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "npm ≥ 8";               npm --version 2>/dev/null   | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "docker ≥ 20.10";        docker --version 2>/dev/null | sed 's/Docker version //' | cut -d',' -f1 | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "solana ≥ 2.1.6";        solana --version 2>/dev/null | awk '{print $2}' | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  printf "%-22s " "arcium ≥ 0.2.0";        arcium --version 2>/dev/null | awk '{print $NF}' | xargs -I{} printf "%b %s\n" "$CHECK" "{}" || printf "%b not found\n" "$CROSS"
  set -e

  # Quick runtime checks (best‑effort)
  if command -v docker >/dev/null 2>&1; then
    log "Testing Docker hello‑world (best‑effort)…"
    if docker run --rm hello-world >/dev/null 2>&1; then
      ok "Docker container run OK."
    else
      warn "Docker run failed. Ensure the Docker daemon is running and you relogged after adding group."
    fi
  fi

  if command -v solana >/dev/null 2>&1; then
    log "Solana current config:"
    solana config get || true
  fi
  line
}

# ========== Main ==========
title

log "Profile file: $PROFILE_FILE"
log "OS detected: $OS"

install_rust
install_nvm_node_lts
install_docker
install_solana
install_arcium_cli
verify_all

printf "\n${BOLD}All done.${RESET} ${CHECK} You are ready to build with Arcium.\n"
printf "${DIM}Tip:${RESET} Restart your terminal or 'source' your profile to load PATH changes:\n"
printf "  ${CYAN}source %s${RESET}\n" "$PROFILE_FILE"
line

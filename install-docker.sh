#!/usr/bin/env bash
set -e

echo ">>> Detecting operating system..."

OS="$(uname -s)"

install_docker_linux() {
  echo ">>> Installing Docker on Linux..."

  # Remove older versions if any
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

  # Update package index
  sudo apt-get update -y

  # Install required packages
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Add Docker’s official GPG key
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # Set up the stable repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Update and install Docker Engine
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Enable and start Docker
  sudo systemctl enable docker
  sudo systemctl start docker

  # Add current user to docker group
  sudo usermod -aG docker "$USER" || true

  echo ">>> Docker installed successfully on Linux!"
  echo ">>> You may need to log out and log back in to use docker without sudo."
}

install_docker_mac() {
  echo ">>> Installing Docker on macOS..."

  # Check if Homebrew is installed
  if ! command -v brew >/dev/null 2>&1; then
    echo ">>> Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Install Docker Desktop via Homebrew Cask
  brew install --cask docker

  echo ">>> Docker Desktop installed on macOS."
  echo ">>> Please open Docker.app manually the first time to finish setup."
}

case "$OS" in
  Linux*)   install_docker_linux ;;
  Darwin*)  install_docker_mac ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

#!/bin/bash

################################################################################
# Arcium Node Automatic Installation Script
# 
# This script automates the complete setup of an Arcium testnet node:
# - Detects OS and installs prerequisites (Rust, Solana CLI, Docker)
# - Installs Arcium CLI and arcup
# - Generates all required keypairs
# - Funds accounts with devnet SOL
# - Initializes node accounts on-chain
# - Creates configuration files
# - Deploys and starts the node
# - Verifies node operation
#
# Usage: curl -sSL https://your-url/arcium-node-autoinstall.sh | bash
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_DIR="$HOME/arcium-node-setup"
NODE_KEYPAIR="$WORKSPACE_DIR/node-keypair.json"
CALLBACK_KEYPAIR="$WORKSPACE_DIR/callback-kp.json"
IDENTITY_KEYPAIR="$WORKSPACE_DIR/identity.pem"
NODE_CONFIG="$WORKSPACE_DIR/node-config.toml"
DOCKER_CONTAINER_NAME="arx-node"
RPC_URL="https://api.devnet.solana.com"

################################################################################
# Utility Functions
################################################################################

print_header() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          Arcium Testnet Node - Automatic Setup                ║"
    echo "║                    v1.0.0                                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        print_info "Detected OS: Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_info "Detected OS: macOS"
    else
        print_error "Unsupported OS: $OSTYPE"
        print_warning "This script supports Linux and macOS only"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is running
is_docker_running() {
    if command_exists docker; then
        docker info >/dev/null 2>&1
        return $?
    fi
    return 1
}

# Check if node container exists
node_container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"
}

# Check if node container is running
is_node_running() {
    docker ps --format '{{.Names}}' | grep -q "^${DOCKER_CONTAINER_NAME}$"
}

################################################################################
# Installation Functions
################################################################################

# Install Rust
install_rust() {
    print_section "Installing Rust"
    
    if command_exists rustc && command_exists cargo; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        print_success "Rust is already installed: v$RUST_VERSION"
        return 0
    fi
    
    print_info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    
    # Source cargo env
    source "$HOME/.cargo/env"
    
    if command_exists rustc; then
        print_success "Rust installed successfully: $(rustc --version)"
    else
        print_error "Rust installation failed"
        exit 1
    fi
}

# Install Solana CLI
install_solana() {
    print_section "Installing Solana CLI"
    
    if command_exists solana; then
        SOLANA_VERSION=$(solana --version | awk '{print $2}')
        print_success "Solana CLI is already installed: v$SOLANA_VERSION"
        
        # Ensure it's configured for devnet
        print_info "Configuring Solana CLI for devnet..."
        solana config set --url devnet >/dev/null 2>&1
        print_success "Solana CLI configured for devnet"
        return 0
    fi
    
    print_info "Installing Solana CLI..."
    sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
    
    # Add to PATH
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    
    if command_exists solana; then
        print_success "Solana CLI installed successfully: $(solana --version)"
        
        # Configure for devnet
        print_info "Configuring for devnet..."
        solana config set --url devnet
        print_success "Configured for devnet"
    else
        print_error "Solana CLI installation failed"
        exit 1
    fi
}

# Install Docker
install_docker() {
    print_section "Installing Docker"
    
    if is_docker_running; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        print_success "Docker is already installed and running: v$DOCKER_VERSION"
        return 0
    fi
    
    if command_exists docker; then
        print_warning "Docker is installed but not running"
        print_info "Attempting to start Docker..."
        
        if [[ "$OS" == "macos" ]]; then
            open -a Docker
            print_info "Waiting for Docker to start..."
            sleep 10
            
            if is_docker_running; then
                print_success "Docker started successfully"
                return 0
            fi
        elif [[ "$OS" == "linux" ]]; then
            sudo systemctl start docker
            if is_docker_running; then
                print_success "Docker started successfully"
                return 0
            fi
        fi
        
        print_error "Could not start Docker. Please start it manually and run this script again."
        exit 1
    fi
    
    print_info "Installing Docker..."
    
    if [[ "$OS" == "linux" ]]; then
        # Install Docker on Linux
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Add user to docker group
        sudo usermod -aG docker "$USER"
        print_warning "You've been added to the docker group. You may need to log out and back in."
        
        # Try to use docker with sudo for this session
        print_info "Using sudo for Docker commands in this session..."
        
    elif [[ "$OS" == "macos" ]]; then
        print_error "Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop"
        print_info "After installation, run this script again."
        exit 1
    fi
    
    if is_docker_running; then
        print_success "Docker installed and running"
    else
        print_error "Docker installation failed or not running"
        exit 1
    fi
}

# Install Arcium CLI
install_arcium() {
    print_section "Installing Arcium CLI"
    
    if command_exists arcium; then
        ARCIUM_VERSION=$(arcium --version 2>/dev/null | head -n1 || echo "unknown")
        print_success "Arcium CLI is already installed: $ARCIUM_VERSION"
        return 0
    fi
    
    print_info "Installing Arcium CLI via arcium-install..."
    curl --proto '=https' --tlsv1.2 -sSfL https://arcium-install.arcium.workers.dev/ | bash
    
    # Source the shell configuration to get arcium in PATH
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$HOME/.zshrc" ]; then
        source "$HOME/.zshrc"
    fi
    
    # Add to current session PATH
    export PATH="$HOME/.arcium/bin:$PATH"
    
    if command_exists arcium; then
        print_success "Arcium CLI installed successfully"
    else
        print_error "Arcium CLI installation failed"
        exit 1
    fi
}

################################################################################
# Node Setup Functions
################################################################################

# Create workspace directory
setup_workspace() {
    print_section "Setting Up Workspace"
    
    if [ -d "$WORKSPACE_DIR" ]; then
        print_warning "Workspace directory already exists: $WORKSPACE_DIR"
    else
        print_info "Creating workspace directory: $WORKSPACE_DIR"
        mkdir -p "$WORKSPACE_DIR"
        print_success "Workspace created"
    fi
    
    cd "$WORKSPACE_DIR"
}

# Get public IP
get_public_ip() {
    print_section "Detecting Public IP Address"
    
    PUBLIC_IP=$(curl -s https://ipecho.net/plain || curl -s https://api.ipify.org || curl -s https://ifconfig.me)
    
    if [ -z "$PUBLIC_IP" ]; then
        print_error "Could not detect public IP address"
        print_info "Please enter your public IP manually:"
        read -r PUBLIC_IP
    fi
    
    print_success "Public IP: $PUBLIC_IP"
}

# Generate keypairs
generate_keypairs() {
    print_section "Generating Keypairs"
    
    # Node keypair
    if [ -f "$NODE_KEYPAIR" ]; then
        print_warning "Node keypair already exists: $NODE_KEYPAIR"
    else
        print_info "Generating node authority keypair..."
        solana-keygen new --outfile "$NODE_KEYPAIR" --no-bip39-passphrase --force
        print_success "Node keypair generated"
    fi
    
    # Callback keypair
    if [ -f "$CALLBACK_KEYPAIR" ]; then
        print_warning "Callback keypair already exists: $CALLBACK_KEYPAIR"
    else
        print_info "Generating callback authority keypair..."
        solana-keygen new --outfile "$CALLBACK_KEYPAIR" --no-bip39-passphrase --force
        print_success "Callback keypair generated"
    fi
    
    # Identity keypair
    if [ -f "$IDENTITY_KEYPAIR" ]; then
        print_warning "Identity keypair already exists: $IDENTITY_KEYPAIR"
    else
        print_info "Generating identity keypair (PKCS#8 format)..."
        openssl genpkey -algorithm Ed25519 -out "$IDENTITY_KEYPAIR"
        print_success "Identity keypair generated"
    fi
    
    # Show public keys
    NODE_PUBKEY=$(solana address --keypair-path "$NODE_KEYPAIR")
    CALLBACK_PUBKEY=$(solana address --keypair-path "$CALLBACK_KEYPAIR")
    
    print_info "Node public key: $NODE_PUBKEY"
    print_info "Callback public key: $CALLBACK_PUBKEY"
}

# Fund accounts
fund_accounts() {
    print_section "Funding Accounts with Devnet SOL"
    
    NODE_PUBKEY=$(solana address --keypair-path "$NODE_KEYPAIR")
    CALLBACK_PUBKEY=$(solana address --keypair-path "$CALLBACK_KEYPAIR")
    
    print_info "Checking node account balance..."
    NODE_BALANCE=$(solana balance "$NODE_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
    
    if (( $(echo "$NODE_BALANCE >= 2" | bc -l) )); then
        print_success "Node account has sufficient balance: $NODE_BALANCE SOL"
    else
        print_info "Requesting airdrop for node account..."
        solana airdrop 2 "$NODE_PUBKEY" -u devnet || print_warning "Airdrop may have failed, check balance manually"
        sleep 2
        print_success "Node account funded"
    fi
    
    print_info "Checking callback account balance..."
    CALLBACK_BALANCE=$(solana balance "$CALLBACK_PUBKEY" -u devnet 2>/dev/null | awk '{print $1}')
    
    if (( $(echo "$CALLBACK_BALANCE >= 2" | bc -l) )); then
        print_success "Callback account has sufficient balance: $CALLBACK_BALANCE SOL"
    else
        print_info "Requesting airdrop for callback account..."
        solana airdrop 2 "$CALLBACK_PUBKEY" -u devnet || print_warning "Airdrop may have failed, check balance manually"
        sleep 2
        print_success "Callback account funded"
    fi
    
    print_info "If airdrops failed, get SOL from https://faucet.solana.com"
}

# Generate node offset
generate_node_offset() {
    # Generate a random 10-digit number
    NODE_OFFSET=$(shuf -i 1000000000-9999999999 -n 1)
    print_info "Generated node offset: $NODE_OFFSET"
}

# Initialize node accounts
initialize_node_accounts() {
    print_section "Initializing Node Accounts On-Chain"
    
    if [ -z "$NODE_OFFSET" ]; then
        generate_node_offset
    fi
    
    print_info "Node offset: $NODE_OFFSET"
    print_info "IP address: $PUBLIC_IP"
    print_info "Initializing accounts (this may take a moment)..."
    
    arcium init-arx-accs \
        --keypair-path "$NODE_KEYPAIR" \
        --callback-keypair-path "$CALLBACK_KEYPAIR" \
        --peer-keypair-path "$IDENTITY_KEYPAIR" \
        --node-offset "$NODE_OFFSET" \
        --ip-address "$PUBLIC_IP" \
        --rpc-url "$RPC_URL" || {
            print_error "Node initialization failed"
            print_warning "This may be due to:"
            print_warning "  - Node offset already in use (try running script again)"
            print_warning "  - Insufficient SOL for transaction fees"
            print_warning "  - RPC endpoint issues"
            exit 1
        }
    
    print_success "Node accounts initialized on-chain"
}

# Create node configuration
create_node_config() {
    print_section "Creating Node Configuration"
    
    if [ -f "$NODE_CONFIG" ]; then
        print_warning "Node config already exists: $NODE_CONFIG"
        print_info "Backing up existing config..."
        cp "$NODE_CONFIG" "$NODE_CONFIG.backup.$(date +%s)"
    fi
    
    print_info "Creating node-config.toml..."
    
    cat > "$NODE_CONFIG" <<EOF
[node]
offset = $NODE_OFFSET
hardware_claim = 0
starting_epoch = 0
ending_epoch = 9223372036854775807

[network]
address = "0.0.0.0"

[solana]
endpoint_rpc = "$RPC_URL"
endpoint_wss = "wss://api.devnet.solana.com"
cluster = "Devnet"
commitment.commitment = "confirmed"
EOF
    
    print_success "Node configuration created"
}

# Deploy node with Docker
deploy_node() {
    print_section "Deploying ARX Node"
    
    # Check if container already exists
    if node_container_exists; then
        if is_node_running; then
            print_warning "Node container is already running"
            print_info "Stopping existing container..."
            docker stop "$DOCKER_CONTAINER_NAME"
        fi
        
        print_info "Removing existing container..."
        docker rm "$DOCKER_CONTAINER_NAME"
    fi
    
    print_info "Pulling latest arcium/arx-node image..."
    docker pull arcium/arx-node:latest
    
    print_info "Starting node container..."
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart unless-stopped \
        -v "$IDENTITY_KEYPAIR:/app/identity.pem:ro" \
        -v "$NODE_KEYPAIR:/app/node-keypair.json:ro" \
        -v "$CALLBACK_KEYPAIR:/app/callback-kp.json:ro" \
        -v "$NODE_CONFIG:/app/node_config.toml:ro" \
        -p 8080:8080 \
        arcium/arx-node:latest
    
    if is_node_running; then
        print_success "Node deployed and running"
    else
        print_error "Node failed to start"
        print_info "Check logs with: docker logs $DOCKER_CONTAINER_NAME"
        exit 1
    fi
}

# Verify node operation
verify_node() {
    print_section "Verifying Node Operation"
    
    print_info "Waiting for node to initialize..."
    sleep 5
    
    if is_node_running; then
        print_success "✓ Node container is running"
        
        print_info "Checking node logs..."
        docker logs --tail 20 "$DOCKER_CONTAINER_NAME"
        
        NODE_PUBKEY=$(solana address --keypair-path "$NODE_KEYPAIR")
        
        print_info "\nNode Information:"
        print_info "  - Container: $DOCKER_CONTAINER_NAME"
        print_info "  - Public Key: $NODE_PUBKEY"
        print_info "  - Node Offset: $NODE_OFFSET"
        print_info "  - Public IP: $PUBLIC_IP"
        print_info "  - Port: 8080"
        
        print_success "\n✓ Node setup complete!"
    else
        print_error "Node is not running"
        print_info "Check logs with: docker logs $DOCKER_CONTAINER_NAME"
        exit 1
    fi
}

# Print summary
print_summary() {
    print_section "Setup Summary"
    
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                  🎉 Setup Completed Successfully! 🎉           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${YELLOW}View logs:${NC}         docker logs -f $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}Stop node:${NC}         docker stop $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}Start node:${NC}        docker start $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}Restart node:${NC}      docker restart $DOCKER_CONTAINER_NAME"
    echo -e "  ${YELLOW}Node status:${NC}       docker ps | grep $DOCKER_CONTAINER_NAME"
    
    echo -e "\n${CYAN}Node Details:${NC}"
    echo -e "  ${YELLOW}Workspace:${NC}         $WORKSPACE_DIR"
    echo -e "  ${YELLOW}Node Pubkey:${NC}       $(solana address --keypair-path "$NODE_KEYPAIR")"
    echo -e "  ${YELLOW}Node Offset:${NC}       $NODE_OFFSET"
    echo -e "  ${YELLOW}Public IP:${NC}         $PUBLIC_IP"
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "  1. Monitor your node logs to ensure it's running correctly"
    echo -e "  2. Join or create a cluster to participate in testnet"
    echo -e "  3. Join Arcium Discord for updates: ${BLUE}https://discord.gg/arcium${NC}"
    
    echo -e "\n${GREEN}Thank you for running an Arcium testnet node!${NC}\n"
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header
    
    # Detect OS
    detect_os
    
    # Install prerequisites
    install_rust
    install_solana
    install_docker
    install_arcium
    
    # Setup workspace
    setup_workspace
    
    # Get public IP
    get_public_ip
    
    # Generate keypairs
    generate_keypairs
    
    # Fund accounts
    fund_accounts
    
    # Initialize node
    initialize_node_accounts
    
    # Create config
    create_node_config
    
    # Deploy node
    deploy_node
    
    # Verify
    verify_node
    
    # Print summary
    print_summary
}

# Run main function
main "$@"

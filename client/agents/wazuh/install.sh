#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     Wazuh Agent Installer                                    ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# This script is called by the main install.sh
# Required env vars: WAZUH_MANAGER, WAZUH_PORT, WAZUH_PROTOCOL, WAZUH_AGENT_GROUP
#                    OS_FAMILY, DRY_RUN

set -euo pipefail

# Inherit logging from parent or define minimal
if ! declare -f info &>/dev/null; then
    info()  { echo "[INFO] $*"; }
    warn()  { echo "[WARN] $*"; }
    error() { echo "[ERROR] $*"; }
fi

run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

# ──────────────────────────────────────────────────────────────────────────────
# Debian/Ubuntu Installation
# ──────────────────────────────────────────────────────────────────────────────
install_debian() {
    info "Setting up Wazuh repository (Debian/Ubuntu)..."
    
    # Install prerequisites
    run_cmd apt-get update
    run_cmd apt-get install -y curl apt-transport-https gnupg
    
    # Add Wazuh GPG key
    run_cmd curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh-archive-keyring.gpg
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/wazuh-archive-keyring.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | \
        tee /etc/apt/sources.list.d/wazuh.list > /dev/null
    
    run_cmd apt-get update
    
    # Install agent
    info "Installing Wazuh agent package..."
    WAZUH_MANAGER="${WAZUH_MANAGER}" run_cmd apt-get install -y wazuh-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# RHEL/CentOS Installation
# ──────────────────────────────────────────────────────────────────────────────
install_rhel() {
    info "Setting up Wazuh repository (RHEL/CentOS)..."
    
    # Add Wazuh GPG key
    run_cmd rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
    
    # Add repository
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
    
    # Install agent
    info "Installing Wazuh agent package..."
    WAZUH_MANAGER="${WAZUH_MANAGER}" run_cmd yum install -y wazuh-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
configure_agent() {
    local config_file="/var/ossec/etc/ossec.conf"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure Wazuh agent"
        return 0
    fi
    
    if [[ ! -f "$config_file" ]]; then
        warn "Config file not found: $config_file"
        return 1
    fi
    
    info "Configuring Wazuh agent..."
    
    # Update manager address
    sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER}</address>|g" "$config_file"
    
    # Update port if specified
    if [[ -n "${WAZUH_PORT:-}" ]]; then
        sed -i "s|<port>.*</port>|<port>${WAZUH_PORT}</port>|g" "$config_file"
    fi
    
    # Update protocol if specified
    if [[ -n "${WAZUH_PROTOCOL:-}" ]]; then
        sed -i "s|<protocol>.*</protocol>|<protocol>${WAZUH_PROTOCOL}</protocol>|g" "$config_file"
    fi
    
    info "Configuration updated"
}

# ──────────────────────────────────────────────────────────────────────────────
# Agent Registration
# ──────────────────────────────────────────────────────────────────────────────
register_agent() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would register agent with manager"
        return 0
    fi
    
    info "Registering agent with Wazuh manager..."
    
    local auth_args=("-m" "${WAZUH_MANAGER}")
    
    # Add agent group if specified
    if [[ -n "${WAZUH_AGENT_GROUP:-}" ]]; then
        auth_args+=("-G" "${WAZUH_AGENT_GROUP}")
    fi
    
    # Add password if specified
    if [[ -n "${WAZUH_REGISTRATION_PASSWORD:-}" ]]; then
        auth_args+=("-P" "${WAZUH_REGISTRATION_PASSWORD}")
    fi
    
    if /var/ossec/bin/agent-auth "${auth_args[@]}"; then
        info "Agent registered successfully"
    else
        warn "Agent registration failed. You may need to register manually."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Management
# ──────────────────────────────────────────────────────────────────────────────
enable_service() {
    info "Enabling and starting Wazuh agent service..."
    
    run_cmd systemctl daemon-reload
    run_cmd systemctl enable wazuh-agent
    run_cmd systemctl start wazuh-agent
    
    if systemctl is-active --quiet wazuh-agent; then
        info "Wazuh agent is running"
    else
        warn "Wazuh agent failed to start"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    info "Starting Wazuh agent installation..."
    info "Manager: ${WAZUH_MANAGER:-not set}"
    info "Agent group: ${WAZUH_AGENT_GROUP:-default}"
    
    # Check if already installed
    if command -v /var/ossec/bin/wazuh-control &>/dev/null; then
        warn "Wazuh agent is already installed. Skipping package installation."
    else
        case "${OS_FAMILY:-debian}" in
            debian) install_debian ;;
            rhel)   install_rhel ;;
            *)      install_debian ;;
        esac
    fi
    
    configure_agent
    register_agent
    enable_service
    
    info "Wazuh agent installation complete"
}

main "$@"

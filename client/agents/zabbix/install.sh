#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     Zabbix Agent Installer                                   ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# This script is called by the main install.sh
# Required env vars: ZABBIX_SERVER, ZABBIX_SERVER_ACTIVE, ZABBIX_HOST_METADATA
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
    info "Installing Zabbix agent (Debian/Ubuntu)..."
    
    # Get OS version for correct repo
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "bookworm")
    
    # Download and install Zabbix repo
    local zabbix_release="zabbix-release_7.0-2+${codename}_all.deb"
    run_cmd wget -q "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/${zabbix_release}" -O /tmp/zabbix-release.deb || \
        run_cmd wget -q "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/${zabbix_release}" -O /tmp/zabbix-release.deb || \
        warn "Could not download Zabbix release package, trying apt directly"
    
    if [[ -f /tmp/zabbix-release.deb ]]; then
        run_cmd dpkg -i /tmp/zabbix-release.deb
        rm -f /tmp/zabbix-release.deb
    fi
    
    run_cmd apt-get update
    run_cmd apt-get install -y zabbix-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# RHEL/CentOS Installation
# ──────────────────────────────────────────────────────────────────────────────
install_rhel() {
    info "Installing Zabbix agent (RHEL/CentOS)..."
    
    # Get major version
    local major_version
    major_version=$(rpm -E %{rhel} 2>/dev/null || echo "9")
    
    # Install Zabbix repo
    run_cmd rpm -Uvh "https://repo.zabbix.com/zabbix/7.0/rhel/${major_version}/x86_64/zabbix-release-7.0-4.el${major_version}.noarch.rpm" || \
        warn "Zabbix repo may already be installed"
    
    run_cmd yum install -y zabbix-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
configure_agent() {
    local config_file="/etc/zabbix/zabbix_agentd.conf"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure Zabbix agent"
        return 0
    fi
    
    if [[ ! -f "$config_file" ]]; then
        warn "Config file not found: $config_file"
        return 1
    fi
    
    info "Configuring Zabbix agent..."
    
    # Backup original config
    cp "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    
    # Update server address
    sed -i "s|^Server=.*|Server=${ZABBIX_SERVER}|" "$config_file"
    sed -i "s|^ServerActive=.*|ServerActive=${ZABBIX_SERVER_ACTIVE:-${ZABBIX_SERVER}}|" "$config_file"
    
    # Set hostname to system hostname
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    sed -i "s|^Hostname=.*|Hostname=${hostname}|" "$config_file"
    
    # Add host metadata for auto-registration (if not already present)
    if ! grep -q "^HostMetadata=" "$config_file"; then
        echo "HostMetadata=${ZABBIX_HOST_METADATA:-linux}" >> "$config_file"
    else
        sed -i "s|^HostMetadata=.*|HostMetadata=${ZABBIX_HOST_METADATA:-linux}|" "$config_file"
    fi
    
    # Configure listen port
    if [[ -n "${ZABBIX_LISTEN_PORT:-}" ]]; then
        sed -i "s|^ListenPort=.*|ListenPort=${ZABBIX_LISTEN_PORT}|" "$config_file"
    fi
    
    # Configure remote commands
    if [[ "${ZABBIX_ENABLE_REMOTE_COMMANDS:-0}" == "1" ]]; then
        if ! grep -q "^EnableRemoteCommands=" "$config_file"; then
            echo "EnableRemoteCommands=1" >> "$config_file"
        else
            sed -i "s|^EnableRemoteCommands=.*|EnableRemoteCommands=1|" "$config_file"
        fi
    fi
    
    info "Configuration updated"
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Management
# ──────────────────────────────────────────────────────────────────────────────
enable_service() {
    info "Enabling and starting Zabbix agent service..."
    
    run_cmd systemctl daemon-reload
    run_cmd systemctl enable zabbix-agent
    run_cmd systemctl restart zabbix-agent
    
    if systemctl is-active --quiet zabbix-agent; then
        info "Zabbix agent is running"
    else
        warn "Zabbix agent failed to start"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    info "Starting Zabbix agent installation..."
    info "Server: ${ZABBIX_SERVER:-not set}"
    info "Host metadata: ${ZABBIX_HOST_METADATA:-linux}"
    
    # Check if already installed
    if command -v zabbix_agentd &>/dev/null; then
        warn "Zabbix agent is already installed. Updating configuration only."
    else
        case "${OS_FAMILY:-debian}" in
            debian) install_debian ;;
            rhel)   install_rhel ;;
            *)      install_debian ;;
        esac
    fi
    
    configure_agent
    enable_service
    
    info "Zabbix agent installation complete"
}

main "$@"

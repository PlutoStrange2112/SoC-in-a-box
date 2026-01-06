#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     Wazuh Manager Installer                                  ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Installs Wazuh Manager with Indexer and Dashboard (all-in-one)
# Required env vars: WAZUH_API_USER, WAZUH_API_PASSWORD, WAZUH_INDEXER_ADMIN_PASSWORD

set -euo pipefail

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

WAZUH_VERSION="4.7"

# ──────────────────────────────────────────────────────────────────────────────
# Prerequisites
# ──────────────────────────────────────────────────────────────────────────────
install_prerequisites() {
    info "Installing prerequisites..."
    
    if [[ "${OS_FAMILY:-debian}" == "debian" ]]; then
        run_cmd apt-get update
        run_cmd apt-get install -y curl apt-transport-https gnupg lsb-release
    else
        run_cmd yum install -y curl gnupg
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Wazuh Installation (Assisted Method)
# ──────────────────────────────────────────────────────────────────────────────
download_installer() {
    info "Downloading Wazuh installer..."
    
    local installer_url="https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"
    
    run_cmd curl -sO "$installer_url"
    run_cmd chmod +x wazuh-install.sh
}

generate_config() {
    info "Generating Wazuh configuration..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would generate config.yml"
        return 0
    fi
    
    local hostname="${SERVER_HOSTNAME:-$(hostname)}"
    local ip="${SERVER_IP:-$(hostname -I | awk '{print $1}')}"
    
    cat > config.yml << EOF
nodes:
  # Wazuh indexer nodes
  indexer:
    - name: ${hostname}
      ip: ${ip}
  
  # Wazuh server nodes
  server:
    - name: ${hostname}
      ip: ${ip}
  
  # Wazuh dashboard nodes
  dashboard:
    - name: ${hostname}
      ip: ${ip}
EOF
    
    info "Configuration generated"
}

install_wazuh_stack() {
    info "Installing Wazuh stack (this may take several minutes)..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would install Wazuh indexer, manager, and dashboard"
        return 0
    fi
    
    # Generate certificates
    info "Generating certificates..."
    ./wazuh-install.sh --generate-config-files
    
    # Install indexer
    info "Installing Wazuh indexer..."
    ./wazuh-install.sh --wazuh-indexer "${SERVER_HOSTNAME:-$(hostname)}"
    
    # Initialize cluster
    ./wazuh-install.sh --start-cluster
    
    # Install manager
    info "Installing Wazuh manager..."
    ./wazuh-install.sh --wazuh-server "${SERVER_HOSTNAME:-$(hostname)}"
    
    # Install dashboard
    info "Installing Wazuh dashboard..."
    ./wazuh-install.sh --wazuh-dashboard "${SERVER_HOSTNAME:-$(hostname)}"
    
    info "Wazuh stack installation complete"
}

# ──────────────────────────────────────────────────────────────────────────────
# Alternative: Package-based Installation
# ──────────────────────────────────────────────────────────────────────────────
install_manager_package_debian() {
    info "Installing Wazuh manager package (Debian/Ubuntu)..."
    
    # Add GPG key
    run_cmd curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh-archive-keyring.gpg
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/wazuh-archive-keyring.gpg] https://packages.wazuh.com/${WAZUH_VERSION}/apt/ stable main" | \
        tee /etc/apt/sources.list.d/wazuh.list > /dev/null
    
    run_cmd apt-get update
    run_cmd apt-get install -y wazuh-manager
}

install_manager_package_rhel() {
    info "Installing Wazuh manager package (RHEL/CentOS)..."
    
    # Add GPG key
    run_cmd rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
    
    # Add repository
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/${WAZUH_VERSION}/yum/
protect=1
EOF
    
    run_cmd yum install -y wazuh-manager
}

# ──────────────────────────────────────────────────────────────────────────────
# Post-Installation
# ──────────────────────────────────────────────────────────────────────────────
configure_api() {
    info "Configuring Wazuh API..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure API user"
        return 0
    fi
    
    # Change default API password
    if [[ -n "${WAZUH_API_PASSWORD:-}" ]]; then
        local hash
        hash=$(echo -n "${WAZUH_API_PASSWORD}" | sha512sum | awk '{print $1}')
        
        # Update API user password
        cat > /var/ossec/api/configuration/security/user_wui.yml << EOF
users:
  - username: ${WAZUH_API_USER:-wazuh-wui}
    password: "${hash}"
EOF
        
        chown wazuh:wazuh /var/ossec/api/configuration/security/user_wui.yml
        chmod 640 /var/ossec/api/configuration/security/user_wui.yml
    fi
}

enable_services() {
    info "Enabling Wazuh services..."
    
    run_cmd systemctl daemon-reload
    
    for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
        if systemctl list-unit-files | grep -q "$svc"; then
            run_cmd systemctl enable "$svc"
            run_cmd systemctl restart "$svc"
        fi
    done
    
    info "Services enabled"
}

print_credentials() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         Wazuh Installation Complete"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Dashboard URL: https://${SERVER_HOSTNAME:-$(hostname)}:5601"
    echo "  API URL:       https://${SERVER_HOSTNAME:-$(hostname)}:55000"
    echo ""
    echo "  Default credentials (CHANGE THESE!):"
    echo "    Username: admin"
    echo "    Password: (check wazuh-install-files.tar in current directory)"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    info "Starting Wazuh Manager installation..."
    
    install_prerequisites
    download_installer
    generate_config
    install_wazuh_stack
    configure_api
    enable_services
    print_credentials
    
    info "Wazuh Manager installation complete"
}

main "$@"

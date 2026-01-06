#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     Zabbix Server Installer                                  ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Installs Zabbix Server with frontend
# Required env vars: ZABBIX_DB_NAME, ZABBIX_DB_USER, ZABBIX_DB_PASSWORD, DB_ROOT_PASSWORD

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

ZABBIX_VERSION="7.0"

# ──────────────────────────────────────────────────────────────────────────────
# Debian/Ubuntu Installation
# ──────────────────────────────────────────────────────────────────────────────
install_zabbix_debian() {
    info "Installing Zabbix Server (Debian/Ubuntu)..."
    
    # Get codename
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "bookworm")
    
    # Download Zabbix repo
    local repo_url="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/debian/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-2+${codename}_all.deb"
    
    run_cmd wget -q "$repo_url" -O /tmp/zabbix-release.deb || \
        run_cmd wget -q "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-2+${codename}_all.deb" -O /tmp/zabbix-release.deb || \
        warn "Could not download Zabbix release package"
    
    if [[ -f /tmp/zabbix-release.deb ]]; then
        run_cmd dpkg -i /tmp/zabbix-release.deb
        rm -f /tmp/zabbix-release.deb
    fi
    
    run_cmd apt-get update
    run_cmd apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# RHEL/CentOS Installation
# ──────────────────────────────────────────────────────────────────────────────
install_zabbix_rhel() {
    info "Installing Zabbix Server (RHEL/CentOS)..."
    
    local major_version
    major_version=$(rpm -E %{rhel} 2>/dev/null || echo "9")
    
    # Install Zabbix repo
    run_cmd rpm -Uvh "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/${major_version}/x86_64/zabbix-release-${ZABBIX_VERSION}-4.el${major_version}.noarch.rpm" || true
    
    run_cmd yum install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-agent
}

# ──────────────────────────────────────────────────────────────────────────────
# Database Import
# ──────────────────────────────────────────────────────────────────────────────
import_schema() {
    info "Importing Zabbix database schema..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would import database schema"
        return 0
    fi
    
    local schema_file="/usr/share/zabbix-sql-scripts/mysql/server.sql.gz"
    
    if [[ -f "$schema_file" ]]; then
        zcat "$schema_file" | mysql -u"${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASSWORD}" "${ZABBIX_DB_NAME}"
        info "Schema imported"
        
        # Disable log_bin_trust_function_creators after import
        mysql -u root -p"${DB_ROOT_PASSWORD}" -e "SET GLOBAL log_bin_trust_function_creators = 0;"
    else
        warn "Schema file not found: $schema_file"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
configure_server() {
    info "Configuring Zabbix server..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure Zabbix server"
        return 0
    fi
    
    local config_file="/etc/zabbix/zabbix_server.conf"
    
    if [[ -f "$config_file" ]]; then
        # Backup original
        cp "$config_file" "${config_file}.bak"
        
        # Set database credentials
        sed -i "s/^# DBPassword=.*/DBPassword=${ZABBIX_DB_PASSWORD}/" "$config_file"
        sed -i "s/^DBPassword=.*/DBPassword=${ZABBIX_DB_PASSWORD}/" "$config_file"
        
        # If DBPassword line doesn't exist, add it
        if ! grep -q "^DBPassword=" "$config_file"; then
            echo "DBPassword=${ZABBIX_DB_PASSWORD}" >> "$config_file"
        fi
    fi
    
    info "Server configured"
}

configure_frontend() {
    info "Configuring Zabbix frontend..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure frontend"
        return 0
    fi
    
    local timezone="${ZABBIX_TIMEZONE:-UTC}"
    local php_conf=""
    
    # Find PHP config for Apache
    if [[ -f /etc/zabbix/apache.conf ]]; then
        php_conf="/etc/zabbix/apache.conf"
    elif [[ -f /etc/apache2/conf-enabled/zabbix.conf ]]; then
        php_conf="/etc/apache2/conf-enabled/zabbix.conf"
    elif [[ -f /etc/httpd/conf.d/zabbix.conf ]]; then
        php_conf="/etc/httpd/conf.d/zabbix.conf"
    fi
    
    if [[ -n "$php_conf" && -f "$php_conf" ]]; then
        sed -i "s|# php_value date.timezone.*|php_value date.timezone ${timezone}|" "$php_conf"
        sed -i "s|php_value date.timezone.*|php_value date.timezone ${timezone}|" "$php_conf"
    fi
    
    # Create frontend config
    local frontend_conf="/etc/zabbix/web/zabbix.conf.php"
    if [[ ! -f "$frontend_conf" ]]; then
        mkdir -p /etc/zabbix/web
        cat > "$frontend_conf" << EOF
<?php
\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = '${ZABBIX_DB_NAME}';
\$DB['USER']     = '${ZABBIX_DB_USER}';
\$DB['PASSWORD'] = '${ZABBIX_DB_PASSWORD}';
\$DB['SCHEMA']   = '';
\$DB['ENCRYPTION'] = false;
\$DB['KEY_FILE'] = '';
\$DB['CERT_FILE'] = '';
\$DB['CA_FILE'] = '';
\$DB['VERIFY_HOST'] = false;
\$DB['CIPHER_LIST'] = '';
\$DB['VAULT_URL'] = '';
\$DB['VAULT_DB_PATH'] = '';
\$DB['VAULT_TOKEN'] = '';
\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '${SERVER_HOSTNAME:-Zabbix}';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF
        chown www-data:www-data "$frontend_conf" 2>/dev/null || chown apache:apache "$frontend_conf" 2>/dev/null || true
        chmod 640 "$frontend_conf"
    fi
    
    info "Frontend configured"
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Management
# ──────────────────────────────────────────────────────────────────────────────
enable_services() {
    info "Enabling Zabbix services..."
    
    run_cmd systemctl daemon-reload
    
    # Restart Apache
    if systemctl list-unit-files | grep -q apache2; then
        run_cmd systemctl restart apache2
        run_cmd systemctl enable apache2
    elif systemctl list-unit-files | grep -q httpd; then
        run_cmd systemctl restart httpd
        run_cmd systemctl enable httpd
    fi
    
    # Enable Zabbix services
    run_cmd systemctl enable zabbix-server zabbix-agent
    run_cmd systemctl restart zabbix-server zabbix-agent
    
    info "Services enabled"
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    info "Starting Zabbix Server installation..."
    
    # Install based on OS
    case "${OS_FAMILY:-debian}" in
        debian) install_zabbix_debian ;;
        rhel)   install_zabbix_rhel ;;
    esac
    
    import_schema
    configure_server
    configure_frontend
    enable_services
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         Zabbix Installation Complete"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Frontend URL: http://${SERVER_HOSTNAME:-$(hostname)}/zabbix"
    echo ""
    echo "  Default credentials:"
    echo "    Username: Admin"
    echo "    Password: zabbix"
    echo ""
    echo "  IMPORTANT: Change the default Admin password immediately!"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    info "Zabbix Server installation complete"
}

main "$@"

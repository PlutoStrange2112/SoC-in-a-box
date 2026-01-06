#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     Database Installer                                       ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# Installs MariaDB or PostgreSQL based on DB_TYPE
# Required env vars: DB_TYPE, DB_ROOT_PASSWORD, ZABBIX_DB_NAME, ZABBIX_DB_USER, ZABBIX_DB_PASSWORD

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

# ──────────────────────────────────────────────────────────────────────────────
# MariaDB Installation
# ──────────────────────────────────────────────────────────────────────────────
install_mariadb_debian() {
    info "Installing MariaDB (Debian/Ubuntu)..."
    
    run_cmd apt-get update
    
    # Pre-configure root password to avoid interactive prompt
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        debconf-set-selections <<< "mariadb-server mysql-server/root_password password ${DB_ROOT_PASSWORD}"
        debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password ${DB_ROOT_PASSWORD}"
    fi
    
    run_cmd apt-get install -y mariadb-server mariadb-client
}

install_mariadb_rhel() {
    info "Installing MariaDB (RHEL/CentOS)..."
    
    run_cmd yum install -y mariadb-server mariadb
}

configure_mariadb() {
    info "Configuring MariaDB..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure MariaDB"
        return 0
    fi
    
    # Start service
    systemctl enable mariadb
    systemctl start mariadb
    
    # Secure installation (non-interactive)
    mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Create Zabbix database and user
    if [[ -n "${ZABBIX_DB_NAME:-}" ]]; then
        info "Creating Zabbix database..."
        mysql -u root -p"${DB_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB_NAME}.* TO '${ZABBIX_DB_USER}'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
EOF
    fi
    
    info "MariaDB configured"
}

# ──────────────────────────────────────────────────────────────────────────────
# PostgreSQL Installation
# ──────────────────────────────────────────────────────────────────────────────
install_postgresql_debian() {
    info "Installing PostgreSQL (Debian/Ubuntu)..."
    
    run_cmd apt-get update
    run_cmd apt-get install -y postgresql postgresql-contrib
}

install_postgresql_rhel() {
    info "Installing PostgreSQL (RHEL/CentOS)..."
    
    run_cmd yum install -y postgresql-server postgresql
    run_cmd postgresql-setup --initdb
}

configure_postgresql() {
    info "Configuring PostgreSQL..."
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure PostgreSQL"
        return 0
    fi
    
    # Start service
    systemctl enable postgresql
    systemctl start postgresql
    
    # Set root password and create Zabbix database
    sudo -u postgres psql << EOF
ALTER USER postgres PASSWORD '${DB_ROOT_PASSWORD}';
EOF
    
    if [[ -n "${ZABBIX_DB_NAME:-}" ]]; then
        info "Creating Zabbix database..."
        sudo -u postgres psql << EOF
CREATE USER ${ZABBIX_DB_USER} WITH PASSWORD '${ZABBIX_DB_PASSWORD}';
CREATE DATABASE ${ZABBIX_DB_NAME} OWNER ${ZABBIX_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${ZABBIX_DB_NAME} TO ${ZABBIX_DB_USER};
EOF
    fi
    
    info "PostgreSQL configured"
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    local db_type="${DB_TYPE:-mariadb}"
    
    info "Starting database installation (${db_type})..."
    
    case "$db_type" in
        mariadb|mysql)
            case "${OS_FAMILY:-debian}" in
                debian) install_mariadb_debian ;;
                rhel)   install_mariadb_rhel ;;
            esac
            configure_mariadb
            ;;
        postgresql|postgres)
            case "${OS_FAMILY:-debian}" in
                debian) install_postgresql_debian ;;
                rhel)   install_postgresql_rhel ;;
            esac
            configure_postgresql
            ;;
        *)
            error "Unknown database type: $db_type"
            exit 1
            ;;
    esac
    
    info "Database installation complete"
}

main "$@"

#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     SoC-in-a-Box Server Installer                            ║
# ║                     Ghost Tech Security Solutions                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false
ENV_FILE="${SCRIPT_DIR}/.env"
LOG_FILE="/var/log/soc-server-install.log"

# ──────────────────────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ──────────────────────────────────────────────────────────────────────────────
# Logging Functions
# ──────────────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${BLUE}[${timestamp}]${NC} ${GREEN}[INFO]${NC} $msg" ;;
        WARN)  echo -e "${BLUE}[${timestamp}]${NC} ${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${BLUE}[${timestamp}]${NC} ${RED}[ERROR]${NC} $msg" ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[${timestamp}]${NC} [DEBUG] $msg" ;;
        STEP)  echo -e "${CYAN}[${timestamp}]${NC} ${CYAN}[STEP]${NC} $msg" ;;
    esac
    
    if [[ "$DRY_RUN" == "false" && -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[${timestamp}] [$level] $msg" >> "$LOG_FILE"
    fi
}

info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }
error() { log ERROR "$@"; }
debug() { log DEBUG "$@"; }
step()  { log STEP "$@"; }

# ──────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ──────────────────────────────────────────────────────────────────────────────
die() {
    error "$1"
    exit 1
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $*"
        return 0
    fi
    debug "Executing: $*"
    "$@"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo $0"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_FAMILY=""
        
        case "$OS_ID" in
            debian|ubuntu|raspbian)
                OS_FAMILY="debian"
                ;;
            rhel|centos|fedora|rocky|almalinux|ol)
                OS_FAMILY="rhel"
                ;;
            *)
                warn "Unknown OS: $OS_ID. Attempting Debian-style installation."
                OS_FAMILY="debian"
                ;;
        esac
        
        info "Detected OS: $OS_ID $OS_VERSION (family: $OS_FAMILY)"
    else
        die "Cannot detect OS. /etc/os-release not found."
    fi
}

check_system_requirements() {
    info "Checking system requirements..."
    
    # Check RAM (minimum 4GB recommended, 8GB preferred)
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    
    if [[ $mem_gb -lt 4 ]]; then
        warn "System has ${mem_gb}GB RAM. Minimum 4GB recommended, 8GB preferred."
    else
        info "System has ${mem_gb}GB RAM"
    fi
    
    # Check disk space (minimum 50GB recommended)
    local disk_avail
    disk_avail=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    
    if [[ $disk_avail -lt 50 ]]; then
        warn "Only ${disk_avail}GB disk space available. Minimum 50GB recommended."
    else
        info "Available disk space: ${disk_avail}GB"
    fi
}

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        die "Environment file not found: $ENV_FILE. Copy .env.template to .env and configure it."
    fi
    
    info "Loading configuration from $ENV_FILE"
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
    
    # Validate required variables
    [[ -z "${SITE_NAME:-}" ]] && die "SITE_NAME is required"
    [[ -z "${SERVER_HOSTNAME:-}" ]] && die "SERVER_HOSTNAME is required"
    [[ -z "${DB_ROOT_PASSWORD:-}" ]] && die "DB_ROOT_PASSWORD is required"
    
    # Validate passwords aren't defaults
    if [[ "${DB_ROOT_PASSWORD}" == "CHANGE_ME_ROOT" ]]; then
        die "You must change DB_ROOT_PASSWORD from the default value"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Component Installation Functions
# ──────────────────────────────────────────────────────────────────────────────
install_database() {
    step "Installing database..."
    
    if [[ -f "${SCRIPT_DIR}/components/database/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/components/database/install.sh"
    else
        die "Database installer not found: ${SCRIPT_DIR}/components/database/install.sh"
    fi
}

install_wazuh() {
    if [[ "${WAZUH_ENABLED:-false}" != "true" ]]; then
        info "Wazuh Manager installation skipped (WAZUH_ENABLED != true)"
        return 0
    fi
    
    step "Installing Wazuh Manager..."
    
    if [[ -f "${SCRIPT_DIR}/components/wazuh-manager/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/components/wazuh-manager/install.sh"
    else
        die "Wazuh installer not found: ${SCRIPT_DIR}/components/wazuh-manager/install.sh"
    fi
}

install_zabbix() {
    if [[ "${ZABBIX_ENABLED:-false}" != "true" ]]; then
        info "Zabbix Server installation skipped (ZABBIX_ENABLED != true)"
        return 0
    fi
    
    step "Installing Zabbix Server..."
    
    if [[ -f "${SCRIPT_DIR}/components/zabbix-server/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/components/zabbix-server/install.sh"
    else
        die "Zabbix installer not found: ${SCRIPT_DIR}/components/zabbix-server/install.sh"
    fi
}

install_nginx() {
    if [[ "${NGINX_ENABLED:-false}" != "true" ]]; then
        info "Nginx installation skipped (NGINX_ENABLED != true)"
        return 0
    fi
    
    step "Installing Nginx reverse proxy..."
    
    if [[ -f "${SCRIPT_DIR}/components/nginx/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/components/nginx/install.sh"
    else
        die "Nginx installer not found: ${SCRIPT_DIR}/components/nginx/install.sh"
    fi
}

configure_firewall() {
    if [[ "${ENABLE_FIREWALL:-false}" != "true" ]]; then
        info "Firewall configuration skipped (ENABLE_FIREWALL != true)"
        return 0
    fi
    
    step "Configuring firewall..."
    
    if command -v ufw &>/dev/null; then
        # UFW (Debian/Ubuntu)
        run_cmd ufw allow 22/tcp                    # SSH
        run_cmd ufw allow 80/tcp                    # HTTP
        run_cmd ufw allow 443/tcp                   # HTTPS
        run_cmd ufw allow 1514/tcp                  # Wazuh agent
        run_cmd ufw allow 1515/tcp                  # Wazuh registration
        run_cmd ufw allow 10051/tcp                 # Zabbix server
        run_cmd ufw allow 10050/tcp                 # Zabbix agent (for self-monitoring)
        run_cmd ufw --force enable
        info "UFW firewall configured"
    elif command -v firewall-cmd &>/dev/null; then
        # firewalld (RHEL/CentOS)
        run_cmd firewall-cmd --permanent --add-service=ssh
        run_cmd firewall-cmd --permanent --add-service=http
        run_cmd firewall-cmd --permanent --add-service=https
        run_cmd firewall-cmd --permanent --add-port=1514/tcp
        run_cmd firewall-cmd --permanent --add-port=1515/tcp
        run_cmd firewall-cmd --permanent --add-port=10051/tcp
        run_cmd firewall-cmd --permanent --add-port=10050/tcp
        run_cmd firewall-cmd --reload
        info "firewalld configured"
    else
        warn "No supported firewall found (ufw or firewalld)"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
SoC-in-a-Box Server Installer v${VERSION}
Ghost Tech Security Solutions

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be done without making changes
    -v, --verbose       Enable verbose output
    -e, --env FILE      Use specified environment file (default: .env)
    --version           Show version

Examples:
    sudo $0                     # Standard installation
    sudo $0 --dry-run           # Preview changes
    sudo $0 -e /path/to/.env    # Use custom env file

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -e|--env)
                ENV_FILE="$2"
                shift 2
                ;;
            --version)
                echo "SoC-in-a-Box Server Installer v${VERSION}"
                exit 0
                ;;
            *)
                die "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         Installation Summary"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Site:        ${SITE_NAME} (${ENVIRONMENT})"
    echo "  Hostname:    ${SERVER_HOSTNAME}"
    echo ""
    echo "  Components Installed:"
    echo "    ✓ Database (${DB_TYPE})"
    [[ "${WAZUH_ENABLED:-false}" == "true" ]] && echo "    ✓ Wazuh Manager"
    [[ "${ZABBIX_ENABLED:-false}" == "true" ]] && echo "    ✓ Zabbix Server"
    [[ "${NGINX_ENABLED:-false}" == "true" ]] && echo "    ✓ Nginx Reverse Proxy"
    echo ""
    echo "  Access URLs:"
    [[ "${WAZUH_ENABLED:-false}" == "true" ]] && echo "    Wazuh Dashboard:  https://${SERVER_DOMAIN:-$SERVER_HOSTNAME}:${WAZUH_DASHBOARD_PORT:-5601}"
    [[ "${ZABBIX_ENABLED:-false}" == "true" ]] && echo "    Zabbix Frontend:  https://${SERVER_DOMAIN:-$SERVER_HOSTNAME}/zabbix"
    echo ""
    echo "  Log file:    ${LOG_FILE}"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    warn "IMPORTANT: Change all default passwords before production use!"
    echo ""
}

main() {
    parse_args "$@"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SoC-in-a-Box Server Installer v${VERSION}                    ║"
    echo "║                     Ghost Tech Security Solutions                            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    [[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN MODE: No changes will be made"
    
    require_root
    load_env
    detect_os
    check_system_requirements
    
    info "Starting SOC server installation for ${SITE_NAME}"
    
    # Export variables for child scripts
    export OS_ID OS_FAMILY OS_VERSION DRY_RUN VERBOSE
    export SITE_NAME ENVIRONMENT SERVER_HOSTNAME SERVER_DOMAIN SERVER_IP
    export DB_TYPE DB_ROOT_PASSWORD DB_HOST DB_PORT
    export ZABBIX_DB_NAME ZABBIX_DB_USER ZABBIX_DB_PASSWORD ZABBIX_TIMEZONE ZABBIX_ADMIN_PASSWORD
    export WAZUH_API_USER WAZUH_API_PASSWORD WAZUH_INDEXER_ADMIN_PASSWORD
    export WAZUH_LISTEN_PORT WAZUH_REGISTRATION_PORT WAZUH_API_PORT WAZUH_INDEXER_PORT WAZUH_DASHBOARD_PORT
    export ZABBIX_SERVER_PORT ZABBIX_FRONTEND_PORT
    export ENABLE_TLS LETSENCRYPT_EMAIL TLS_CERT_PATH TLS_KEY_PATH
    
    # Install components in order (dependencies first)
    install_database
    install_wazuh
    install_zabbix
    install_nginx
    configure_firewall
    
    print_summary
    
    info "Installation complete!"
}

main "$@"

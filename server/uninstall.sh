#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     SoC-in-a-Box Server Uninstaller                          ║
# ║                     Ghost Tech Security Solutions                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

VERSION="1.0.0"
DRY_RUN=false
VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    esac
}

info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }
error() { log ERROR "$@"; }

die() {
    error "$1"
    exit 1
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

require_root() {
    [[ $EUID -ne 0 ]] && die "This script must be run as root. Use: sudo $0"
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        
        case "$OS_ID" in
            debian|ubuntu|raspbian) OS_FAMILY="debian" ;;
            rhel|centos|fedora|rocky|almalinux|ol) OS_FAMILY="rhel" ;;
            *) OS_FAMILY="debian" ;;
        esac
    fi
}

uninstall_nginx() {
    info "Removing Nginx..."
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        run_cmd systemctl stop nginx
    fi
    
    if [[ "$OS_FAMILY" == "debian" ]]; then
        dpkg -l | grep -q nginx && run_cmd apt-get remove -y nginx nginx-common
    else
        rpm -q nginx &>/dev/null && run_cmd yum remove -y nginx
    fi
    
    # Remove configs
    [[ -d /etc/nginx/sites-enabled ]] && run_cmd rm -f /etc/nginx/sites-enabled/soc-*
    
    info "Nginx removed"
}

uninstall_zabbix() {
    info "Removing Zabbix Server..."
    
    # Stop services
    for svc in zabbix-server zabbix-agent; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            run_cmd systemctl stop "$svc"
        fi
    done
    
    if [[ "$OS_FAMILY" == "debian" ]]; then
        dpkg -l | grep -q zabbix && run_cmd apt-get remove -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent
    else
        rpm -q zabbix-server-mysql &>/dev/null && run_cmd yum remove -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-agent
    fi
    
    info "Zabbix Server removed"
}

uninstall_wazuh() {
    info "Removing Wazuh Manager..."
    
    # Stop all Wazuh services
    for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            run_cmd systemctl stop "$svc"
        fi
    done
    
    if [[ "$OS_FAMILY" == "debian" ]]; then
        dpkg -l | grep -q wazuh && run_cmd apt-get remove -y wazuh-manager wazuh-indexer wazuh-dashboard
    else
        rpm -q wazuh-manager &>/dev/null && run_cmd yum remove -y wazuh-manager wazuh-indexer wazuh-dashboard
    fi
    
    # Clean up data directories (CAUTION: data loss)
    warn "Wazuh data directories NOT removed. Remove manually if needed:"
    warn "  /var/ossec"
    warn "  /var/lib/wazuh-indexer"
    
    info "Wazuh Manager removed"
}

uninstall_database() {
    info "Stopping database services..."
    
    for svc in mariadb mysql postgresql; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            run_cmd systemctl stop "$svc"
        fi
    done
    
    warn "Database packages NOT removed to prevent data loss."
    warn "Remove manually if needed: apt remove mariadb-server / yum remove mariadb-server"
    
    info "Database services stopped"
}

usage() {
    cat << EOF
SoC-in-a-Box Server Uninstaller v${VERSION}

Usage: $0 [OPTIONS]

Options:
    -h, --help      Show this help message
    -d, --dry-run   Show what would be done without making changes
    -v, --verbose   Enable verbose output
    --all           Remove all components (default)
    --wazuh         Remove Wazuh only
    --zabbix        Remove Zabbix only
    --nginx         Remove Nginx only
    --database      Stop database only (does not remove)

EOF
}

main() {
    local remove_wazuh=false
    local remove_zabbix=false
    local remove_nginx=false
    local remove_database=false
    local remove_all=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            --all) remove_all=true; shift ;;
            --wazuh) remove_wazuh=true; remove_all=false; shift ;;
            --zabbix) remove_zabbix=true; remove_all=false; shift ;;
            --nginx) remove_nginx=true; remove_all=false; shift ;;
            --database) remove_database=true; remove_all=false; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SoC-in-a-Box Server Uninstaller                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    [[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN MODE: No changes will be made"
    
    require_root
    detect_os
    
    if [[ "$remove_all" == "true" ]]; then
        uninstall_nginx
        uninstall_zabbix
        uninstall_wazuh
        uninstall_database
    else
        [[ "$remove_nginx" == "true" ]] && uninstall_nginx
        [[ "$remove_zabbix" == "true" ]] && uninstall_zabbix
        [[ "$remove_wazuh" == "true" ]] && uninstall_wazuh
        [[ "$remove_database" == "true" ]] && uninstall_database
    fi
    
    info "Uninstallation complete!"
    warn "Review /var/log, /var/lib, and /etc for remaining data and configuration files."
}

main "$@"

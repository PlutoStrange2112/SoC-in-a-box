#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     SoC-in-a-Box Client Uninstaller                          ║
# ║                     Ghost Tech Security Solutions                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

uninstall_wazuh() {
    info "Removing Wazuh agent..."
    
    # Stop service
    if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
        run_cmd systemctl stop wazuh-agent
    fi
    
    # Remove package
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if dpkg -l | grep -q wazuh-agent; then
            run_cmd apt-get remove -y wazuh-agent
            run_cmd apt-get autoremove -y
        fi
    else
        if rpm -q wazuh-agent &>/dev/null; then
            run_cmd yum remove -y wazuh-agent
        fi
    fi
    
    # Clean up config
    [[ -d /var/ossec ]] && run_cmd rm -rf /var/ossec
    
    info "Wazuh agent removed"
}

uninstall_zabbix() {
    info "Removing Zabbix agent..."
    
    # Stop service
    if systemctl is-active --quiet zabbix-agent 2>/dev/null; then
        run_cmd systemctl stop zabbix-agent
    fi
    
    # Remove package
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if dpkg -l | grep -q zabbix-agent; then
            run_cmd apt-get remove -y zabbix-agent
            run_cmd apt-get autoremove -y
        fi
    else
        if rpm -q zabbix-agent &>/dev/null; then
            run_cmd yum remove -y zabbix-agent
        fi
    fi
    
    # Clean up config
    [[ -f /etc/zabbix/zabbix_agentd.conf ]] && run_cmd rm -f /etc/zabbix/zabbix_agentd.conf
    
    info "Zabbix agent removed"
}

uninstall_clamav() {
    info "Removing ClamAV..."
    
    # Stop services
    for svc in clamav-daemon clamav-freshclam clamd freshclam; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            run_cmd systemctl stop "$svc"
        fi
    done
    
    # Remove package
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if dpkg -l | grep -q clamav; then
            run_cmd apt-get remove -y clamav clamav-daemon
            run_cmd apt-get autoremove -y
        fi
    else
        if rpm -q clamav &>/dev/null; then
            run_cmd yum remove -y clamav clamav-update clamd
        fi
    fi
    
    # Remove cron job
    [[ -f /etc/cron.d/clamav-scan ]] && run_cmd rm -f /etc/cron.d/clamav-scan
    
    info "ClamAV removed"
}

usage() {
    cat << EOF
SoC-in-a-Box Client Uninstaller v${VERSION}

Usage: $0 [OPTIONS]

Options:
    -h, --help      Show this help message
    -d, --dry-run   Show what would be done without making changes
    -v, --verbose   Enable verbose output
    --all           Remove all agents (default)
    --wazuh         Remove Wazuh agent only
    --zabbix        Remove Zabbix agent only
    --clamav        Remove ClamAV only

EOF
}

main() {
    local remove_wazuh=false
    local remove_zabbix=false
    local remove_clamav=false
    local remove_all=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            --all) remove_all=true; shift ;;
            --wazuh) remove_wazuh=true; remove_all=false; shift ;;
            --zabbix) remove_zabbix=true; remove_all=false; shift ;;
            --clamav) remove_clamav=true; remove_all=false; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SoC-in-a-Box Client Uninstaller                          ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    [[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN MODE: No changes will be made"
    
    require_root
    detect_os
    
    if [[ "$remove_all" == "true" ]]; then
        uninstall_wazuh
        uninstall_zabbix
        uninstall_clamav
    else
        [[ "$remove_wazuh" == "true" ]] && uninstall_wazuh
        [[ "$remove_zabbix" == "true" ]] && uninstall_zabbix
        [[ "$remove_clamav" == "true" ]] && uninstall_clamav
    fi
    
    info "Uninstallation complete!"
}

main "$@"

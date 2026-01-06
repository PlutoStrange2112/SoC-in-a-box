#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     SoC-in-a-Box Client Installer                            ║
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
LOG_FILE="/var/log/soc-install.log"

# ──────────────────────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    esac
    
    # Also write to log file if not dry run
    if [[ "$DRY_RUN" == "false" && -w "$(dirname "$LOG_FILE")" ]]; then
        echo "[${timestamp}] [$level] $msg" >> "$LOG_FILE"
    fi
}

info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }
error() { log ERROR "$@"; }
debug() { log DEBUG "$@"; }

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

check_network() {
    info "Testing network connectivity to SOC server..."
    
    if ! command -v ping &> /dev/null; then
        warn "ping not available, skipping connectivity check"
        return 0
    fi
    
    if ping -c 1 -W 5 "$SOC_IP" &> /dev/null; then
        info "SOC server ($SOC_IP) is reachable"
    else
        warn "Cannot reach SOC server at $SOC_IP. Installation will continue but agents may not register."
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
    [[ -z "${SOC_IP:-}" ]] && die "SOC_IP is required"
}

# ──────────────────────────────────────────────────────────────────────────────
# Agent Installation Functions
# ──────────────────────────────────────────────────────────────────────────────
install_wazuh() {
    if [[ "${WAZUH_ENABLED:-false}" != "true" ]]; then
        info "Wazuh agent installation skipped (WAZUH_ENABLED != true)"
        return 0
    fi
    
    info "Installing Wazuh agent..."
    
    if [[ -f "${SCRIPT_DIR}/agents/wazuh/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/agents/wazuh/install.sh"
    else
        die "Wazuh installer not found: ${SCRIPT_DIR}/agents/wazuh/install.sh"
    fi
}

install_zabbix() {
    if [[ "${ZABBIX_ENABLED:-false}" != "true" ]]; then
        info "Zabbix agent installation skipped (ZABBIX_ENABLED != true)"
        return 0
    fi
    
    info "Installing Zabbix agent..."
    
    if [[ -f "${SCRIPT_DIR}/agents/zabbix/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/agents/zabbix/install.sh"
    else
        die "Zabbix installer not found: ${SCRIPT_DIR}/agents/zabbix/install.sh"
    fi
}

install_clamav() {
    if [[ "${CLAMAV_ENABLED:-false}" != "true" ]]; then
        info "ClamAV installation skipped (CLAMAV_ENABLED != true)"
        return 0
    fi
    
    info "Installing ClamAV..."
    
    if [[ -f "${SCRIPT_DIR}/agents/clamav/install.sh" ]]; then
        run_cmd bash "${SCRIPT_DIR}/agents/clamav/install.sh"
    else
        die "ClamAV installer not found: ${SCRIPT_DIR}/agents/clamav/install.sh"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
SoC-in-a-Box Client Installer v${VERSION}
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
                echo "SoC-in-a-Box Client Installer v${VERSION}"
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
    echo "  SOC Server:  ${SOC_IP}"
    echo ""
    echo "  Agents Installed:"
    [[ "${WAZUH_ENABLED:-false}" == "true" ]] && echo "    ✓ Wazuh Agent"
    [[ "${ZABBIX_ENABLED:-false}" == "true" ]] && echo "    ✓ Zabbix Agent"
    [[ "${CLAMAV_ENABLED:-false}" == "true" ]] && echo "    ✓ ClamAV"
    echo ""
    echo "  Log file:    ${LOG_FILE}"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
}

main() {
    parse_args "$@"
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                     SoC-in-a-Box Client Installer v${VERSION}                    ║"
    echo "║                     Ghost Tech Security Solutions                            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    [[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN MODE: No changes will be made"
    
    require_root
    load_env
    detect_os
    check_network
    
    info "Starting agent installation for ${SITE_NAME} (${ENVIRONMENT})"
    
    # Export variables for child scripts
    export OS_ID OS_FAMILY OS_VERSION DRY_RUN VERBOSE
    export SITE_NAME ENVIRONMENT SOC_IP
    export WAZUH_MANAGER WAZUH_PORT WAZUH_PROTOCOL WAZUH_AGENT_GROUP WAZUH_REGISTRATION_PASSWORD
    export ZABBIX_SERVER ZABBIX_SERVER_ACTIVE ZABBIX_HOST_METADATA ZABBIX_HOST_GROUP ZABBIX_LISTEN_PORT ZABBIX_ENABLE_REMOTE_COMMANDS
    export CLAMAV_SCAN_PATHS CLAMAV_SCHEDULE CLAMAV_LOG_FILE
    
    install_wazuh
    install_zabbix
    install_clamav
    
    print_summary
    
    info "Installation complete!"
}

main "$@"

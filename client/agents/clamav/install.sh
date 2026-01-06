#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     ClamAV Installer                                         ║
# ║                     SoC-in-a-Box Component                                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# This script is called by the main install.sh
# Required env vars: CLAMAV_SCAN_PATHS, CLAMAV_SCHEDULE, CLAMAV_LOG_FILE
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
    info "Installing ClamAV (Debian/Ubuntu)..."
    
    run_cmd apt-get update
    run_cmd apt-get install -y clamav clamav-daemon clamav-freshclam
}

# ──────────────────────────────────────────────────────────────────────────────
# RHEL/CentOS Installation
# ──────────────────────────────────────────────────────────────────────────────
install_rhel() {
    info "Installing ClamAV (RHEL/CentOS)..."
    
    # Enable EPEL if not already
    run_cmd yum install -y epel-release
    run_cmd yum install -y clamav clamav-update clamd
}

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
configure_clamav() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would configure ClamAV"
        return 0
    fi
    
    info "Configuring ClamAV..."
    
    # Configure freshclam for Debian-based systems
    local freshclam_conf="/etc/clamav/freshclam.conf"
    if [[ -f "$freshclam_conf" ]]; then
        # Comment out Example line if present
        sed -i 's/^Example/#Example/' "$freshclam_conf"
    fi
    
    # Configure clamd for RHEL-based systems
    local clamd_conf="/etc/clamd.d/scan.conf"
    if [[ -f "$clamd_conf" ]]; then
        sed -i 's/^Example/#Example/' "$clamd_conf"
        # Set local socket
        sed -i 's|^#LocalSocket .*|LocalSocket /run/clamd.scan/clamd.sock|' "$clamd_conf"
    fi
    
    # Create log directory
    local log_dir
    log_dir=$(dirname "${CLAMAV_LOG_FILE:-/var/log/clamav/scan.log}")
    mkdir -p "$log_dir"
    chown clamav:clamav "$log_dir" 2>/dev/null || true
    
    info "Configuration complete"
}

# ──────────────────────────────────────────────────────────────────────────────
# Scheduled Scan Setup
# ──────────────────────────────────────────────────────────────────────────────
setup_scheduled_scan() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would setup scheduled scan"
        return 0
    fi
    
    info "Setting up scheduled scans..."
    
    local scan_paths="${CLAMAV_SCAN_PATHS:-/home,/srv}"
    local schedule="${CLAMAV_SCHEDULE:-0 2 * * *}"
    local log_file="${CLAMAV_LOG_FILE:-/var/log/clamav/scan.log}"
    
    # Convert comma-separated paths to space-separated for clamscan
    local paths_arg
    paths_arg=$(echo "$scan_paths" | tr ',' ' ')
    
    # Create cron job
    cat > /etc/cron.d/clamav-scan << EOF
# ClamAV scheduled scan - SoC-in-a-Box
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

${schedule} root /usr/bin/clamscan -r ${paths_arg} --quiet --infected --log=${log_file} 2>&1 | logger -t clamav-scan
EOF
    
    chmod 644 /etc/cron.d/clamav-scan
    
    info "Scheduled scan configured: ${schedule}"
    info "Paths to scan: ${paths_arg}"
}

# ──────────────────────────────────────────────────────────────────────────────
# Update Virus Definitions
# ──────────────────────────────────────────────────────────────────────────────
update_definitions() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY-RUN] Would update virus definitions"
        return 0
    fi
    
    info "Updating virus definitions (this may take a moment)..."
    
    # Stop freshclam service temporarily to run manual update
    systemctl stop clamav-freshclam 2>/dev/null || true
    
    if freshclam --quiet; then
        info "Virus definitions updated successfully"
    else
        warn "Failed to update virus definitions. They will be updated automatically later."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Service Management
# ──────────────────────────────────────────────────────────────────────────────
enable_service() {
    info "Enabling ClamAV services..."
    
    run_cmd systemctl daemon-reload
    
    # Enable freshclam (auto-update service)
    if systemctl list-unit-files | grep -q clamav-freshclam; then
        run_cmd systemctl enable clamav-freshclam
        run_cmd systemctl start clamav-freshclam
        info "clamav-freshclam service enabled"
    fi
    
    # Enable clamd if using on-access scanning (optional)
    if systemctl list-unit-files | grep -q "clamd@scan"; then
        run_cmd systemctl enable clamd@scan
        run_cmd systemctl start clamd@scan
        info "clamd@scan service enabled"
    elif systemctl list-unit-files | grep -q clamav-daemon; then
        run_cmd systemctl enable clamav-daemon
        run_cmd systemctl start clamav-daemon
        info "clamav-daemon service enabled"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
main() {
    info "Starting ClamAV installation..."
    info "Scan paths: ${CLAMAV_SCAN_PATHS:-/home,/srv}"
    info "Schedule: ${CLAMAV_SCHEDULE:-0 2 * * *}"
    
    # Check if already installed
    if command -v clamscan &>/dev/null; then
        warn "ClamAV is already installed. Updating configuration only."
    else
        case "${OS_FAMILY:-debian}" in
            debian) install_debian ;;
            rhel)   install_rhel ;;
            *)      install_debian ;;
        esac
    fi
    
    configure_clamav
    update_definitions
    setup_scheduled_scan
    enable_service
    
    info "ClamAV installation complete"
}

main "$@"

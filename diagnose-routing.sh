#!/bin/bash
#
# Diagnose Routing Issues
#
# Checks what's managing routes and why they can't be added
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_section "ROUTING DIAGNOSTICS"

# Step 1: Check all routes
log_info "Step 1: All routes in system"
ip route show || log_warn "No routes found"

# Step 2: Check routes by table
log_info ""
log_info "Step 2: Routes by table"
ip route show table all || log_warn "Could not show all tables"

# Step 3: Check routing rules
log_info ""
log_info "Step 3: Routing rules"
ip rule show || log_warn "Could not show rules"

# Step 4: Check interface status
log_info ""
log_info "Step 4: Interface status"
ip link show wwan0 || log_warn "wwan0 not found"

# Step 5: Check IP addresses
log_info ""
log_info "Step 5: IP addresses on wwan0"
ip addr show wwan0 || log_warn "Could not show wwan0 addresses"

# Step 6: Check if NetworkManager is managing routes
log_info ""
log_info "Step 6: NetworkManager status"
if systemctl is-active --quiet NetworkManager; then
    log_info "NetworkManager is RUNNING"
    log_info "Checking NetworkManager connections:"
    nmcli connection show || true
    log_info ""
    log_info "Checking NetworkManager devices:"
    nmcli device show wwan0 || log_warn "wwan0 not in NetworkManager"
else
    log_info "NetworkManager is NOT running"
fi

# Step 7: Check if systemd-networkd is managing routes
log_info ""
log_info "Step 7: systemd-networkd status"
if systemctl is-active --quiet systemd-networkd; then
    log_info "systemd-networkd is RUNNING"
    log_info "Checking networkd status:"
    networkctl status || true
else
    log_info "systemd-networkd is NOT running"
fi

# Step 8: Try to add a test route
log_info ""
log_info "Step 8: Testing route addition"
log_info "Attempting to add test route..."

if ip route add 192.0.2.0/24 via 10.53.12.34 dev wwan0 2>&1; then
    log_info "✓ Test route added successfully"
    log_info "Removing test route..."
    ip route del 192.0.2.0/24 via 10.53.12.34 dev wwan0 2>/dev/null || true
else
    log_error "✗ Failed to add test route"
    log_error "This indicates a system-level routing issue"
fi

# Step 9: Check kernel routing
log_info ""
log_info "Step 9: Kernel routing info"
cat /proc/net/route || log_warn "Could not read /proc/net/route"

# Step 10: Check sysctl settings
log_info ""
log_info "Step 10: Relevant sysctl settings"
sysctl net.ipv4.ip_forward || true
sysctl net.ipv4.conf.all.rp_filter || true
sysctl net.ipv4.conf.wwan0.rp_filter 2>/dev/null || log_warn "Could not check wwan0 rp_filter"

log_section "DIAGNOSTICS COMPLETE"

exit 0

#!/bin/bash
#
# Fix DNS Resolution Issues
#
# This script fixes DNS resolution problems by adding fallback DNS servers
# to /etc/resolv.conf when the carrier DNS (e.g., 172.26.38.2) fails to
# resolve some domains.
#
# Usage: sudo ./fix-dns.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "DNS Resolution Fix Tool"
log_info "========================"
echo ""

# Step 1: Show current DNS configuration
log_info "Step 1: Current DNS configuration"
if [[ -f /etc/resolv.conf ]]; then
    log_debug "Contents of /etc/resolv.conf:"
    cat /etc/resolv.conf | while read line; do
        echo "  $line"
    done
else
    log_warn "/etc/resolv.conf not found"
fi
echo ""

# Step 2: Get modem DNS if available
log_info "Step 2: Checking modem DNS configuration"
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -n "$MODEM_ID" ]]; then
    BEARER_ID=$((MODEM_ID + 1))
    log_info "Found modem $MODEM_ID, bearer $BEARER_ID"
    
    MMCLI_OUTPUT=$(mmcli -b $BEARER_ID 2>/dev/null || true)
    if [[ -n "$MMCLI_OUTPUT" ]]; then
        CARRIER_DNS=$(echo "$MMCLI_OUTPUT" | grep -A 5 "IPv4 configuration" | grep "dns:" | head -1 | awk '{print $NF}')
        if [[ -n "$CARRIER_DNS" ]]; then
            log_info "Carrier DNS: $CARRIER_DNS"
        else
            log_warn "No carrier DNS found in modem configuration"
            CARRIER_DNS=""
        fi
    else
        log_warn "Could not retrieve bearer information"
        CARRIER_DNS=""
    fi
else
    log_warn "No modem found"
    CARRIER_DNS=""
fi
echo ""

# Step 3: Build DNS configuration with fallback servers
log_info "Step 3: Building DNS configuration with fallback servers"

# Start with carrier DNS if available
if [[ -n "$CARRIER_DNS" ]]; then
    DNS_CONFIG="nameserver $CARRIER_DNS"
    log_info "Primary DNS: $CARRIER_DNS (carrier)"
else
    DNS_CONFIG="nameserver 8.8.8.8"
    log_info "Primary DNS: 8.8.8.8 (Google - no carrier DNS available)"
fi

# Add fallback DNS servers
DNS_CONFIG="$DNS_CONFIG"$'\n'"nameserver 8.8.8.8"
DNS_CONFIG="$DNS_CONFIG"$'\n'"nameserver 1.1.1.1"
log_info "Fallback DNS: 8.8.8.8 (Google), 1.1.1.1 (Cloudflare)"
echo ""

# Step 4: Check if systemd-resolved is managing DNS
log_info "Step 4: Checking DNS management system"
if systemctl is-active --quiet systemd-resolved; then
    log_warn "systemd-resolved is running and may override /etc/resolv.conf"
    log_info "Attempting to configure DNS via resolvectl..."
    
    # Configure DNS for wwan0 interface
    if ip link show wwan0 &>/dev/null; then
        if [[ -n "$CARRIER_DNS" ]]; then
            resolvectl dns wwan0 $CARRIER_DNS 8.8.8.8 1.1.1.1 2>/dev/null || log_warn "Failed to set DNS via resolvectl"
        else
            resolvectl dns wwan0 8.8.8.8 1.1.1.1 2>/dev/null || log_warn "Failed to set DNS via resolvectl"
        fi
        log_info "✓ DNS configured via resolvectl for wwan0"
    else
        log_warn "wwan0 interface not found, skipping resolvectl configuration"
    fi
    echo ""
fi

# Step 5: Write to /etc/resolv.conf
log_info "Step 5: Writing DNS configuration to /etc/resolv.conf"

# Backup existing resolv.conf
if [[ -f /etc/resolv.conf ]]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    log_info "Backed up existing /etc/resolv.conf"
fi

# Write new configuration
if echo -e "$DNS_CONFIG" > /etc/resolv.conf 2>/dev/null; then
    log_info "✓ DNS configuration written successfully"
else
    log_error "Failed to write /etc/resolv.conf"
    exit 1
fi
echo ""

# Step 6: Verify configuration
log_info "Step 6: Verifying new DNS configuration"
log_debug "New /etc/resolv.conf contents:"
cat /etc/resolv.conf | while read line; do
    echo "  $line"
done
echo ""

# Step 7: Test DNS resolution
log_info "Step 7: Testing DNS resolution"

# Test with common domains
TEST_DOMAINS=("google.com" "cloudflare.com" "github.com")
PASSED=0
FAILED=0

for domain in "${TEST_DOMAINS[@]}"; do
    if nslookup "$domain" &>/dev/null; then
        log_info "✓ $domain resolves successfully"
        PASSED=$((PASSED + 1))
    else
        log_error "✗ $domain failed to resolve"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
log_info "DNS Resolution Test Results"
log_info "============================"
log_info "Passed: $PASSED / ${#TEST_DOMAINS[@]}"
log_info "Failed: $FAILED / ${#TEST_DOMAINS[@]}"
echo ""

if [[ $FAILED -eq 0 ]]; then
    log_info "✓ All DNS tests passed!"
    log_info ""
    log_info "Your /etc/resolv.conf now contains:"
    log_info "  1. Carrier DNS (if available): $CARRIER_DNS"
    log_info "  2. Google DNS: 8.8.8.8"
    log_info "  3. Cloudflare DNS: 1.1.1.1"
    log_info ""
    log_info "DNS queries will try the carrier DNS first, then fallback to"
    log_info "public DNS servers if the carrier DNS fails to resolve a domain."
    exit 0
else
    log_warn "Some DNS tests failed"
    log_info "This may indicate network connectivity issues beyond DNS configuration"
    log_info "Try running: sudo /opt/cellular/cellular-debug.sh test"
    exit 1
fi

#!/bin/bash
#
# Diagnose Cellular Connection Issues
#
# Checks signal strength, modem temperature, network registration, and other factors
# that could cause connection drops
#
# Usage: sudo ./diagnose-connection.sh
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

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_section "CELLULAR CONNECTION DIAGNOSTICS"

# Get modem ID
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    log_error "No modem found"
    exit 1
fi

BEARER_ID=$((MODEM_ID + 1))

log_info "Modem ID: $MODEM_ID"
log_info "Bearer ID: $BEARER_ID"

# Step 1: Signal Strength
log_section "SIGNAL STRENGTH"

SIGNAL=$(mmcli -m $MODEM_ID 2>/dev/null | grep -i "signal quality" | awk '{print $NF}')
if [[ -n "$SIGNAL" ]]; then
    log_info "Signal quality: $SIGNAL"
    
    # Interpret signal strength
    SIGNAL_NUM=${SIGNAL%\%}
    if [[ $SIGNAL_NUM -lt 20 ]]; then
        log_error "✗ VERY WEAK signal (< 20%)"
        log_error "  This will cause frequent disconnections"
        log_error "  Try: Move antenna, change location, or check antenna connection"
    elif [[ $SIGNAL_NUM -lt 50 ]]; then
        log_warn "⚠ WEAK signal (20-50%)"
        log_warn "  Connection may be unstable"
    elif [[ $SIGNAL_NUM -lt 75 ]]; then
        log_info "✓ FAIR signal (50-75%)"
    else
        log_info "✓ GOOD signal (> 75%)"
    fi
else
    log_warn "Could not determine signal strength"
fi

# Step 2: Network Registration
log_section "NETWORK REGISTRATION"

REG_STATUS=$(mmcli -m $MODEM_ID 2>/dev/null | grep -i "state:" | head -1 | awk '{print $NF}')
log_info "Registration state: $REG_STATUS"

if [[ "$REG_STATUS" == "registered" ]]; then
    log_info "✓ Registered with network"
elif [[ "$REG_STATUS" == "searching" ]]; then
    log_warn "⚠ Searching for network"
elif [[ "$REG_STATUS" == "denied" ]]; then
    log_error "✗ Registration denied (SIM issue?)"
else
    log_warn "⚠ Unexpected registration state: $REG_STATUS"
fi

# Step 3: Network Operator
log_section "NETWORK OPERATOR"

OPERATOR=$(mmcli -m $MODEM_ID 2>/dev/null | grep -i "operator name:" | sed 's/.*operator name:[[:space:]]*//')
if [[ -n "$OPERATOR" ]]; then
    log_info "Operator: $OPERATOR"
else
    log_warn "Could not determine operator"
fi

# Step 4: Connection Status
log_section "CONNECTION STATUS"

if mmcli -b $BEARER_ID &>/dev/null; then
    CONNECTED=$(mmcli -b $BEARER_ID 2>/dev/null | grep -i "connected:" | awk '{print $NF}')
    log_info "Bearer connected: $CONNECTED"
    
    if [[ "$CONNECTED" == "yes" ]]; then
        log_info "✓ Bearer is connected"
    else
        log_warn "⚠ Bearer is not connected"
    fi
else
    log_warn "Could not check bearer status"
fi

# Step 5: Modem Temperature (if available)
log_section "MODEM TEMPERATURE"

TEMP=$(mmcli -m $MODEM_ID --command='AT+CTEMP?' 2>/dev/null | grep "CTEMP:" | sed 's/.*CTEMP: //' | awk '{print $1}')
if [[ -n "$TEMP" ]]; then
    log_info "Modem temperature: ${TEMP}°C"
    
    if [[ $TEMP -gt 60 ]]; then
        log_error "✗ OVERHEATING (> 60°C)"
        log_error "  Modem may throttle or disconnect"
        log_error "  Try: Improve ventilation, reduce usage, check power supply"
    elif [[ $TEMP -gt 50 ]]; then
        log_warn "⚠ HOT (50-60°C)"
        log_warn "  Monitor temperature"
    else
        log_info "✓ Normal temperature"
    fi
else
    log_warn "Could not determine modem temperature"
fi

# Step 6: Modem Status
log_section "MODEM STATUS"

mmcli -m $MODEM_ID 2>/dev/null | head -20

# Step 7: Bearer Status
log_section "BEARER STATUS"

if mmcli -b $BEARER_ID &>/dev/null; then
    mmcli -b $BEARER_ID 2>/dev/null | head -20
else
    log_warn "Could not get bearer status"
fi

# Step 8: Interface Status
log_section "INTERFACE STATUS"

ip addr show wwan0 2>/dev/null || log_warn "wwan0 not found"

# Step 9: Routes
log_section "ROUTES"

ip route show dev wwan0 2>/dev/null || log_warn "No routes for wwan0"

# Step 10: DNS
log_section "DNS CONFIGURATION"

cat /etc/resolv.conf

# Step 11: Recommendations
log_section "RECOMMENDATIONS"

if [[ $SIGNAL_NUM -lt 50 ]]; then
    log_warn "1. SIGNAL STRENGTH: Weak signal detected"
    log_warn "   - Move antenna to better location"
    log_warn "   - Check antenna connection"
    log_warn "   - Try different location"
fi

if [[ $TEMP -gt 50 ]]; then
    log_warn "2. TEMPERATURE: Modem is hot"
    log_warn "   - Ensure adequate ventilation"
    log_warn "   - Check power supply quality"
    log_warn "   - Reduce continuous usage"
fi

log_info "3. MONITORING: Run continuous monitor"
log_info "   tail -f /var/log/cellular/auto-recover.log"

log_info "4. LOGS: Check ModemManager logs"
log_info "   sudo journalctl -u ModemManager -f"

log_section "DIAGNOSTICS COMPLETE"

exit 0

#!/bin/bash
#
# SIM7080 Modem Initialization Script
#
# Initializes the SIM7080 modem with proper AT commands
# to ensure stable connection and network registration
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

log_section "SIM7080 MODEM INITIALIZATION"

# Step 1: Check if modem is on USB
log_info "Step 1: Checking if modem is on USB..."
if lsusb | grep -i "1e0e:9205" &>/dev/null; then
    log_info "✓ SIM7080 found on USB"
else
    log_error "✗ SIM7080 not found on USB"
    log_error "Check USB cable connection"
    exit 1
fi

# Step 2: Check serial devices
log_info ""
log_info "Step 2: Checking serial devices..."
if ls /dev/ttyUSB* &>/dev/null; then
    log_info "✓ Serial devices found:"
    ls -la /dev/ttyUSB*
else
    log_error "✗ No /dev/ttyUSB devices found"
    exit 1
fi

# Step 3: Stop ModemManager
log_info ""
log_info "Step 3: Stopping ModemManager..."
systemctl stop ModemManager
sleep 2
log_info "✓ ModemManager stopped"

# Step 4: Send initialization AT commands
log_info ""
log_info "Step 4: Sending initialization AT commands to modem..."

# Use ttyUSB2 (usually the AT command port for SIM7080)
TTY_PORT="/dev/ttyUSB2"

if [[ ! -e "$TTY_PORT" ]]; then
    log_warn "Port $TTY_PORT not found, trying ttyUSB0..."
    TTY_PORT="/dev/ttyUSB0"
fi

log_info "Using port: $TTY_PORT"

# Function to send AT command
send_at_command() {
    local cmd="$1"
    local description="$2"
    
    log_info "  Sending: $cmd"
    
    # Send command with timeout
    (echo -e "$cmd\r"; sleep 0.5) | timeout 2 cat > "$TTY_PORT" 2>/dev/null || true
    sleep 1
}

# Initialize modem
log_info "Initializing modem..."
send_at_command "AT" "Test connection"
send_at_command "ATE0" "Disable echo"
send_at_command "AT+CFUN=1" "Set full functionality"
send_at_command "AT+CPIN?" "Check SIM status"
send_at_command "AT+COPS=0" "Set automatic network selection"
send_at_command "AT+CREG=1" "Enable registration unsolicited result codes"

log_info "✓ AT commands sent"

# Step 5: Start ModemManager
log_info ""
log_info "Step 5: Starting ModemManager..."
systemctl start ModemManager
log_info "Waiting for ModemManager to initialize..."
sleep 5
log_info "✓ ModemManager started"

# Step 6: Wait for modem detection
log_info ""
log_info "Step 6: Waiting for modem detection..."
RETRY=0
MAX_RETRIES=15
MODEM_ID=""

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    MODEM_OUTPUT=$(mmcli -L 2>&1)
    MODEM_ID=$(echo "$MODEM_OUTPUT" | grep -oP 'Modem/\K[0-9]+' | head -1)
    
    if [[ -n "$MODEM_ID" ]]; then
        log_info "✓ Modem detected!"
        log_info "Modem ID: $MODEM_ID"
        break
    else
        RETRY=$((RETRY + 1))
        if [[ $RETRY -lt $MAX_RETRIES ]]; then
            log_warn "Modem not detected yet, retrying... ($RETRY/$MAX_RETRIES)"
            sleep 1
        fi
    fi
done

if [[ -z "$MODEM_ID" ]]; then
    log_error "✗ Modem detection failed after $MAX_RETRIES attempts"
    log_error ""
    log_error "Last mmcli output:"
    mmcli -L || true
    exit 1
fi

# Step 7: Check modem status
log_info ""
log_info "Step 7: Checking modem status..."
mmcli -m $MODEM_ID | head -20

# Step 8: Wait for network registration
log_info ""
log_info "Step 8: Waiting for network registration..."
RETRY=0
MAX_RETRIES=30

while [[ $RETRY -lt $MAX_RETRIES ]]; do
    STATE=$(mmcli -m $MODEM_ID 2>/dev/null | grep "state:" | head -1 | awk '{print $NF}')
    
    if [[ "$STATE" == "registered" ]] || [[ "$STATE" == "connected" ]]; then
        log_info "✓ Modem registered: $STATE"
        break
    fi
    
    RETRY=$((RETRY + 1))
    if [[ $((RETRY % 5)) -eq 0 ]]; then
        log_warn "Still waiting for registration... ($RETRY/$MAX_RETRIES) - State: $STATE"
    fi
    sleep 1
done

if [[ "$STATE" != "registered" ]] && [[ "$STATE" != "connected" ]]; then
    log_warn "Modem not registered after $MAX_RETRIES seconds"
    log_warn "Current state: $STATE"
    log_warn "This may be due to:"
    log_warn "  - No cellular signal in area"
    log_warn "  - SIM card not active"
    log_warn "  - Carrier restrictions"
fi

log_section "INITIALIZATION COMPLETE"
log_info "SIM7080 modem initialized successfully!"
log_info ""
log_info "Modem status:"
mmcli -m $MODEM_ID | grep -E "state:|signal|operator"
log_info ""
log_info "Next steps:"
log_info "  1. Run: sudo /opt/cellular/connect-cellular-robust.sh"
log_info "  2. Or run: sudo /opt/cellular/cellular-debug.sh status"

exit 0

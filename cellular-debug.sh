#!/bin/bash
#
# Cellular Modem Debugging Script
# 
# This script helps diagnose and troubleshoot cellular modem issues
# on Raspberry Pi 4 with SIMCOM SIM7600G-H
#
# Usage: sudo ./cellular-debug.sh [command]
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

# Auto-detect modem ID (handles re-enumeration after restart)
MODEM_ID=$(mmcli -L 2>/dev/null | grep -oP 'Modem/\K[0-9]+' | head -1)
if [[ -z "$MODEM_ID" ]]; then
    MODEM_ID=0  # Default to 0 if not found
fi

# Bearer ID is typically modem_id + 1
BEARER_ID=$((MODEM_ID + 1))

# Command to run
COMMAND="${1:-status}"

case $COMMAND in
    status|check)
        log_section "MODEM STATUS CHECK"
        
        log_info "Checking ModemManager service..."
        if systemctl is-active --quiet ModemManager; then
            log_info "ModemManager is RUNNING"
        else
            log_error "ModemManager is NOT RUNNING"
            log_info "Starting ModemManager..."
            systemctl start ModemManager
            sleep 2
        fi
        
        log_info ""
        log_info "Available modems:"
        mmcli -L
        
        log_info ""
        log_info "Modem 0 details:"
        mmcli -m 0 | head -20
        
        log_info ""
        log_info "Modem 0 signal strength:"
        mmcli -m 0 | grep -i signal
        
        log_info ""
        log_info "Modem 0 network:"
        mmcli -m 0 | grep -i network
        
        log_info ""
        log_info "Bearer status:"
        mmcli -b 1 2>/dev/null || log_warn "No bearer found"
        
        log_info ""
        log_info "Interface status:"
        ip addr show wwan0 2>/dev/null || log_warn "wwan0 interface not found"
        
        log_info ""
        log_info "Routes:"
        ip route show dev wwan0 2>/dev/null || log_warn "No routes for wwan0"
        
        log_info ""
        log_info "DNS configuration:"
        cat /etc/resolv.conf
        ;;
        
    connect)
        log_section "CONNECTING MODEM"
        
        log_info "Step 1: Enabling modem..."
        mmcli -m 0 --enable
        sleep 2
        
        log_info "Step 2: Creating bearer..."
        mmcli -m 0 --create-bearer="apn=ereseller,ip-type=ipv4v6"
        sleep 2
        
        log_info "Step 3: Connecting bearer..."
        mmcli -b 1 --connect
        sleep 2
        
        log_info "Step 4: Bringing up interface..."
        ip link set wwan0 up
        sleep 2
        
        log_info "Step 5: Retrieving configuration..."
        mmcli -b 1
        
        log_info "Connection complete. Run 'sudo ./cellular-debug.sh status' to verify."
        ;;
        
    disconnect)
        log_section "DISCONNECTING MODEM"
        
        log_info "Step 1: Disconnecting bearer..."
        mmcli -b 1 --disconnect 2>/dev/null || log_warn "Bearer already disconnected"
        sleep 2
        
        log_info "Step 2: Bringing down interface..."
        ip link set wwan0 down 2>/dev/null || log_warn "Interface already down"
        
        log_info "Step 3: Disabling modem..."
        mmcli -m 0 --disable
        
        log_info "Disconnection complete."
        ;;
        
    test)
        log_section "CONNECTIVITY TEST"
        
        log_info "Testing interface configuration..."
        if ip addr show wwan0 | grep -q "inet "; then
            log_info "Interface has IPv4 address"
            ip addr show wwan0 | grep inet
        else
            log_error "Interface has no IPv4 address"
            exit 1
        fi
        
        log_info ""
        log_info "Testing default route..."
        if ip route show dev wwan0 | grep -q "default"; then
            log_info "Default route configured"
            ip route show dev wwan0 | grep default
        else
            log_error "No default route"
            exit 1
        fi
        
        log_info ""
        log_info "Testing DNS resolution..."
        if nslookup google.com &>/dev/null; then
            log_info "DNS resolution PASSED"
        else
            log_warn "DNS resolution FAILED (may be carrier restriction)"
        fi
        
        log_info ""
        log_info "Testing ICMP ping to 8.8.8.8..."
        if ping -c 1 -I wwan0 8.8.8.8 &>/dev/null; then
            log_info "ICMP ping PASSED"
        else
            log_warn "ICMP ping FAILED (may be carrier restriction)"
        fi
        
        log_info ""
        log_info "Testing HTTP connectivity..."
        if curl --interface wwan0 -s -m 5 https://httpbin.org/ip &>/dev/null; then
            log_info "HTTP connectivity PASSED"
            curl --interface wwan0 -s https://httpbin.org/ip
        else
            log_warn "HTTP connectivity FAILED"
        fi
        ;;
        
    signal)
        log_section "SIGNAL STRENGTH"
        
        log_info "Modem signal information:"
        mmcli -m 0 | grep -A 10 "Signal quality"
        
        log_info ""
        log_info "Detailed signal stats:"
        mmcli -m 0 --command='AT+CSQ' 2>/dev/null || log_warn "Could not retrieve signal stats"
        ;;
        
    sim)
        log_section "SIM CARD STATUS"
        
        log_info "SIM card information:"
        mmcli -m 0 | grep -A 5 "SIM"
        
        log_info ""
        log_info "SIM PIN status:"
        mmcli -m 0 --command='AT+CPIN?' 2>/dev/null || log_warn "Could not retrieve PIN status"
        ;;
        
    network)
        log_section "NETWORK INFORMATION"
        
        log_info "Registered network:"
        mmcli -m 0 --command='AT+COPS?' 2>/dev/null || log_warn "Could not retrieve network info"
        
        log_info ""
        log_info "Available networks:"
        mmcli -m 0 --command='AT+COPS=?' 2>/dev/null || log_warn "Could not scan networks"
        ;;
        
    logs)
        log_section "RECENT SYSTEM LOGS"
        
        log_info "ModemManager logs (last 20 lines):"
        journalctl -u ModemManager -n 20 --no-pager
        
        log_info ""
        log_info "Cellular connection logs (if available):"
        journalctl -u cellular-connect.service -n 20 --no-pager 2>/dev/null || log_warn "No cellular-connect.service logs"
        ;;
        
    reset)
        log_section "RESETTING MODEM"
        
        log_warn "This will reset the modem connection!"
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Step 1: Disconnecting..."
            mmcli -b 1 --disconnect 2>/dev/null || true
            sleep 2
            
            log_info "Step 2: Disabling modem..."
            mmcli -m 0 --disable
            sleep 3
            
            log_info "Step 3: Enabling modem..."
            mmcli -m 0 --enable
            sleep 2
            
            log_info "Modem reset complete."
        else
            log_info "Reset cancelled."
        fi
        ;;
        
    help|--help|-h)
        cat << EOF
Cellular Modem Debugging Script

Usage: sudo ./cellular-debug.sh [command]

Commands:
  status       Show current modem and connection status
  connect      Connect the modem (manual connection)
  disconnect   Disconnect the modem
  test         Run connectivity tests
  signal       Show signal strength information
  sim          Show SIM card status
  network      Show network information
  logs         Show recent system logs
  reset        Reset the modem (disconnect and reconnect)
  help         Show this help message

Examples:
  sudo ./cellular-debug.sh status
  sudo ./cellular-debug.sh test
  sudo ./cellular-debug.sh signal
  sudo ./cellular-debug.sh reset

EOF
        ;;
        
    *)
        log_error "Unknown command: $COMMAND"
        echo "Run 'sudo ./cellular-debug.sh help' for usage information"
        exit 1
        ;;
esac

exit 0

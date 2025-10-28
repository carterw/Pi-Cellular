#!/bin/bash
#
# Cellular Configuration File
#
# This file contains carrier-specific settings used by all cellular scripts.
# Modify this file to change APN or other carrier settings.
#
# Usage: source /path/to/cellular-config.sh
#

# ============================================
# CARRIER CONFIGURATION
# ============================================

# Access Point Name (APN)
# Change this to your carrier's APN
# Examples:
#   - ereseller (current)
#   - verizon (Verizon)
#   - iot.1nce.net (1NCE)
#   - m2m.vodafone.com (Vodafone)
#   - lte-m.vodafone.de (Vodafone LTE-M)
CELLULAR_APN="ereseller"

# IP Type
# Options: ipv4, ipv6, ipv4v6
CELLULAR_IP_TYPE="ipv4v6"

# ============================================
# INTERFACE CONFIGURATION
# ============================================

# Cellular interface name
CELLULAR_INTERFACE="wwan0"

# Route metric for cellular (higher = lower priority)
# WiFi typically uses metric 600, so cellular should be higher
# to prefer WiFi when both are available
CELLULAR_ROUTE_METRIC="700"

# MTU (Maximum Transmission Unit)
# Typical for cellular: 1430
# Standard Ethernet: 1500
CELLULAR_MTU="1430"

# ============================================
# CONNECTIVITY TESTING
# ============================================

# IP address to test connectivity
# Using 8.8.8.8 (Google DNS) as default
CONNECTIVITY_TEST_IP="8.8.8.8"

# Hostname to test DNS resolution
CONNECTIVITY_TEST_HOST="google.com"

# ============================================
# TIMEOUTS AND RETRIES
# ============================================

# Timeout for ping tests (seconds)
PING_TIMEOUT="5"

# Timeout for DNS resolution tests (seconds)
DNS_TIMEOUT="3"

# Maximum attempts for bearer reconnection
MAX_RECONNECT_ATTEMPTS="3"

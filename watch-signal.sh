#!/bin/bash

# Watch and report signal strength every 2 seconds
# Automatically detect the modem number

# Detect modem number
MODEM_NUMBER=$(mmcli -L | grep -oP '(?<=Modem )(\d+)' | head -1)

if [ -z "$MODEM_NUMBER" ]; then
    echo "Error: No modem found. Ensure ModemManager is running and a modem is connected."
    exit 1
fi

echo "Watching signal strength for modem $MODEM_NUMBER..."
watch -n 2 "mmcli -m $MODEM_NUMBER | grep -i signal"

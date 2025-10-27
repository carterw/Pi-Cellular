# Cellular Modem Scripts - Quick Start Guide

## Overview

Five scripts work together to manage and debug your SIMCOM SIM7600G-H cellular modem on Raspberry Pi:

1. **connect-cellular-robust.sh** - Production connection script with modem state management (runs on Pi)
2. **connect-cellular-dynamic.sh** - Alternative connection script with manual IP configuration (runs on Pi)
3. **auto-recover.sh** - Continuous monitoring daemon for connection stability (runs on Pi)
4. **setup-dns-routes.sh** - DNS and route configuration helper (runs on Pi)
5. **cellular-debug.sh** - Debugging and diagnostics (runs on Pi)

---

## Quick Start

### Step 1: Deploy Scripts to Remote Pi

From your local machine:

```bash
cd /home/bill/speedcam
chmod +x cellular-remote-deploy.sh
./cellular-remote-deploy.sh pi@192.168.1.100
```

Replace `192.168.1.100` with your Pi's IP address or hostname.

### Step 2: SSH into the Remote Pi

```bash
ssh pi@192.168.1.100
```

### Step 3: Check Modem Status

```bash
sudo ~/speedcam/cellular/cellular-debug.sh status
```

### Step 4: Connect the Modem

```bash
# Recommended: Use robust script for production
sudo ~/speedcam/cellular/connect-cellular-robust.sh

# Alternative: Use dynamic script for manual configuration inspection
sudo ~/speedcam/cellular/connect-cellular-dynamic.sh
```

### Step 5: Start Auto-Recovery Daemon (Optional but Recommended)

```bash
sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &
```

### Step 6: Verify Connectivity

```bash
sudo ~/speedcam/cellular/cellular-debug.sh test
```

---

## Script Details

### connect-cellular-robust.sh (Recommended for Production)

**Purpose**: Connect cellular modem with robust modem state management

**Features**:

- Handles various modem states (disabled, searching, registered, connected)
- Disconnects existing bearers before creating new ones
- Automatic interface management (brings wwan0 up if needed)
- Delegates DNS/routes configuration to `setup-dns-routes.sh`
- Comprehensive error handling and logging
- Colored output for easy reading
- Automatic connectivity verification
- Designed to work with `auto-recover.sh` daemon

**Usage**:
```bash
sudo ~/speedcam/cellular/connect-cellular-robust.sh
```

**When to use**:

- Production deployments
- Automated/daemon usage
- When you want modular configuration (DNS/routes handled separately)
- For use with `auto-recover.sh` monitoring

---

### connect-cellular-dynamic.sh (Alternative)

**Purpose**: Connect cellular modem with manual IP configuration

**Features**:

- Manually extracts and configures IP addresses from modem
- Works reliably after each reboot
- Comprehensive error handling
- Colored output for easy reading
- Automatic connectivity verification
- Detailed debugging output for configuration extraction

**Usage**:
```bash
sudo ~/speedcam/cellular/connect-cellular-dynamic.sh
```

**Output Example**:
```
[INFO] Starting cellular connection setup...
[INFO] Step 1: Enabling modem 0...
[INFO] Modem enabled successfully
[INFO] Step 2: Creating bearer with APN=ereseller, IP-Type=ipv4v6...
[INFO] Bearer created successfully
...
[INFO] Cellular connection established!
==========================================
Interface: wwan0
IP Address: 10.19.145.184/28
Gateway: 10.19.145.185
DNS: 172.26.38.2
MTU: 1430
==========================================
```

**Troubleshooting**:
- If it fails, check modem status first: `sudo cellular-debug.sh status`
- If "Failed to retrieve IP configuration", increase sleep time in script
- If connectivity test fails, check carrier restrictions with `cellular-debug.sh test`

**When to use**:
- Troubleshooting and detailed inspection of configuration
- When you want to see exact IP addresses extracted from modem
- For understanding network configuration details

---

### auto-recover.sh (Continuous Monitoring Daemon)

**Purpose**: Continuously monitor and recover cellular connection

**Features**:

- Runs as a background daemon (every 30 seconds by default)
- Checks routes, DNS, IP connectivity, and DNS resolution
- Automatically reconfigures if any check fails
- Detects and fixes connection loss automatically
- Comprehensive logging for debugging
- Configurable check interval

**Usage**:
```bash
# Start daemon with 30-second interval
sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &

# Monitor daemon output
tail -f ~/speedcam/cellular/auto-recover.log

# Stop daemon
sudo pkill -f auto-recover.sh
```

**What it checks**:

- Routes exist and are correct
- DNS is configured
- IP connectivity (ping 8.8.8.8)
- DNS resolution (nslookup google.com)

**When to use**:

- Production deployments requiring high availability
- Long-running systems where connection stability is critical
- Paired with `connect-cellular-robust.sh` for automated recovery

---

### setup-dns-routes.sh (Configuration Helper)

**Purpose**: Configure DNS and routes for cellular connection

**Features**:

- Handles both systemd-resolved and /etc/resolv.conf
- Calculates correct subnet routes for any prefix length (/24 to /32)
- Configures DNS servers automatically
- Fallback to 8.8.8.8 if modem doesn't provide DNS
- Comprehensive error handling

**Usage**:
```bash
# Standalone usage
sudo ~/speedcam/cellular/setup-dns-routes.sh

# Called automatically by connect-cellular-robust.sh
```

**When to use**:
- Called automatically by `connect-cellular-robust.sh`
- Manual reconfiguration of routes/DNS if needed
- Troubleshooting DNS or routing issues

---

### cellular-debug.sh

**Purpose**: Diagnose and troubleshoot modem issues

**Commands**:

#### `status` - Show current state
```bash
sudo ~/speedcam/cellular-debug.sh status
```
Shows modem details, bearer status, interface configuration, and routes.

#### `test` - Run connectivity tests
```bash
sudo ~/speedcam/cellular-debug.sh test
```
Tests:
- IPv4 address assignment
- Default route configuration
- DNS resolution
- ICMP ping to 8.8.8.8
- HTTP connectivity

#### `signal` - Check signal strength
```bash
sudo ~/speedcam/cellular-debug.sh signal
```
Shows signal quality and detailed signal statistics.

#### `sim` - Check SIM card status
```bash
sudo ~/speedcam/cellular-debug.sh sim
```
Shows SIM information and PIN status.

#### `network` - Show network information
```bash
sudo ~/speedcam/cellular-debug.sh network
```
Shows registered network and available networks.

#### `connect` - Manual connection
```bash
sudo ~/speedcam/cellular-debug.sh connect
```
Manually connect modem (useful for testing).

#### `disconnect` - Disconnect modem
```bash
sudo ~/speedcam/cellular-debug.sh disconnect
```
Safely disconnect the modem.

#### `reset` - Reset modem
```bash
sudo ~/speedcam/cellular-debug.sh reset
```
Perform a full modem reset (disconnect and reconnect).

#### `logs` - View system logs
```bash
sudo ~/speedcam/cellular-debug.sh logs
```
Shows recent ModemManager and cellular connection logs.

#### `help` - Show help
```bash
sudo ~/speedcam/cellular-debug.sh help
```

---

### cellular-remote-deploy.sh

**Purpose**: Deploy scripts from local machine to remote Pi

**Usage**:
```bash
./cellular-remote-deploy.sh [user@host]
```

**Examples**:
```bash
./cellular-remote-deploy.sh pi@192.168.1.100
./cellular-remote-deploy.sh pi@speedcam.local
./cellular-remote-deploy.sh pi@10.19.145.184
```

**What it does**:
1. Tests SSH connection to remote Pi
2. Creates remote directory
3. Copies all scripts and documentation
4. Makes scripts executable
5. Verifies deployment

**Requirements**:
- SSH access to remote Pi
- `scp` command available (usually included with SSH)
- Remote user has sudo access

---

## Typical Workflow

### First-Time Setup (Production)

```bash
# SSH to Pi
ssh pi@192.168.1.100

# Check modem status
sudo ~/speedcam/cellular/cellular-debug.sh status

# Connect using robust script
sudo ~/speedcam/cellular/connect-cellular-robust.sh

# Verify connectivity
sudo ~/speedcam/cellular/cellular-debug.sh test

# Start auto-recovery daemon (recommended)
sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &
```

### First-Time Setup (Troubleshooting)

```bash
# SSH to Pi
ssh pi@192.168.1.100

# Check modem status
sudo ~/speedcam/cellular/cellular-debug.sh status

# Connect using dynamic script for detailed inspection
sudo ~/speedcam/cellular/connect-cellular-dynamic.sh

# Verify connectivity
sudo ~/speedcam/cellular/cellular-debug.sh test
```

### Daily Use

```bash
# SSH to Pi
ssh pi@192.168.1.100

# Check status
sudo ~/speedcam/cellular/cellular-debug.sh status

# If disconnected, reconnect (auto-recover daemon should handle this)
sudo ~/speedcam/cellular/connect-cellular-robust.sh

# Verify connectivity
sudo ~/speedcam/cellular/cellular-debug.sh test
```

### Monitoring Auto-Recovery Daemon

```bash
# Monitor daemon logs
tail -f ~/speedcam/cellular/auto-recover.log

# Check if daemon is running
ps aux | grep auto-recover.sh

# Stop daemon if needed
sudo pkill -f auto-recover.sh
```

### Troubleshooting

```bash
# Check signal strength
sudo ~/speedcam/cellular/cellular-debug.sh signal

# Check SIM status
sudo ~/speedcam/cellular/cellular-debug.sh sim

# View recent logs
sudo ~/speedcam/cellular/cellular-debug.sh logs

# Reset modem
sudo ~/speedcam/cellular/cellular-debug.sh reset

# Manual connectivity test
sudo ~/speedcam/cellular/cellular-debug.sh test

# Emergency modem reset (if stuck)
sudo bash ~/speedcam/cellular/reset-modem.sh
```

---

## Automating at Boot

### Option 1: systemd Service with Auto-Recovery (Recommended)

On the remote Pi, create `/etc/systemd/system/cellular-connect.service`:

```ini
[Unit]
Description=Cellular Modem Connection
After=network.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/pi/speedcam/cellular/connect-cellular-robust.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Create `/etc/systemd/system/cellular-auto-recover.service`:

```ini
[Unit]
Description=Cellular Auto-Recovery Daemon
After=cellular-connect.service
Wants=cellular-connect.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'exec /home/pi/speedcam/cellular/auto-recover.sh 30'
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Then enable both:
```bash
sudo systemctl daemon-reload
sudo systemctl enable cellular-connect.service cellular-auto-recover.service
sudo systemctl start cellular-connect.service cellular-auto-recover.service
```

Check status:
```bash
sudo systemctl status cellular-connect.service
sudo systemctl status cellular-auto-recover.service
sudo journalctl -u cellular-connect.service -f
sudo journalctl -u cellular-auto-recover.service -f
```

### Option 2: rc.local

Add to `/etc/rc.local` before `exit 0`:

```bash
/home/pi/speedcam/cellular/connect-cellular-robust.sh >> /var/log/cellular-connect.log 2>&1 &
sleep 5
nohup /home/pi/speedcam/cellular/auto-recover.sh 30 >> /var/log/cellular-auto-recover.log 2>&1 &
```

---

## Common Issues and Solutions

### Issue: "Cannot connect to host via SSH"

**Solution**:
1. Verify Pi is on network: `ping 192.168.1.100`
2. Check SSH is enabled: `sudo systemctl status ssh`
3. Verify username: try `ssh pi@...` or `ssh ubuntu@...`
4. Check firewall: ensure port 22 is open

### Issue: "Failed to retrieve IP configuration"

**Solution**:
1. Check modem is connected: `sudo cellular-debug.sh status`
2. Increase sleep time in script (modem may be slow to connect)
3. Check bearer is connected: `mmcli -b 1`

### Issue: "Cannot reach 8.8.8.8"

**Solution**:
1. This is often normal for cellular carriers (they may block external traffic)
2. Test with your actual server instead
3. Check DNS resolution: `nslookup google.com`

### Issue: "ModemManager is not running"

**Solution**:
```bash
sudo systemctl start ModemManager
sudo systemctl enable ModemManager
```

### Issue: "wwan0 interface not found"

**Solution**:
1. Check modem is enabled: `mmcli -m 0`
2. Check bearer is created: `mmcli -b 1`
3. Restart ModemManager: `sudo systemctl restart ModemManager`

---

## Monitoring

### Real-time monitoring

```bash
# Watch modem status
watch -n 1 'sudo mmcli -m 0 | grep -E "(State|Signal|Network)"'

# Watch interface status
watch -n 1 'ip addr show wwan0'

# Watch logs
sudo journalctl -u cellular-connect.service -f
```

### Periodic checks

```bash
# Create a cron job to check connectivity every 5 minutes
# Edit crontab:
crontab -e

# Add this line:
*/5 * * * * /home/pi/speedcam/cellular-debug.sh test >> /tmp/cellular-test.log 2>&1
```

---

## File Locations

After deployment, scripts are located at:

```
/home/pi/speedcam/cellular/
├── connect-cellular-robust.sh       # Production connection script (recommended)
├── connect-cellular-dynamic.sh      # Alternative connection script
├── auto-recover.sh                  # Continuous monitoring daemon
├── setup-dns-routes.sh              # DNS and route configuration helper
├── reset-modem.sh                   # Emergency modem reset
├── cellular-debug.sh                # Debugging and diagnostics
└── CELLULAR_SCRIPTS_README.md       # This file
```

---

## Support

For detailed technical information, see `CELLULAR_SETUP_GUIDE.md`.

For quick help on any script:
```bash
sudo ~/speedcam/cellular-debug.sh help
```

---

## Script Comparison

| Feature | Dynamic | Robust | Auto-Recover |
|---------|---------|--------|--------------|
| IP Configuration | Manual extraction | Delegated to helper | N/A |
| Modem State Management | Basic | Advanced | N/A |
| Bearer Cleanup | No | Yes | N/A |
| DNS/Routes | Manual | Delegated | Monitors |
| Continuous Monitoring | No | No | Yes |
| Connection Recovery | Manual | Manual | Automatic |
| Best For | Troubleshooting | Production | High Availability |

---

## Recommended Setup

**For Production Deployments:**
1. Use `connect-cellular-robust.sh` for initial connection
2. Run `auto-recover.sh` daemon for continuous monitoring
3. Set up systemd services for automatic startup

**For Troubleshooting:**
1. Use `connect-cellular-dynamic.sh` to see detailed configuration
2. Use `cellular-debug.sh` for diagnostics
3. Check logs with `journalctl` or tail auto-recover.log

---

## Next Steps

1. SSH to Pi: `ssh pi@<ip>`
2. Check status: `sudo ~/speedcam/cellular/cellular-debug.sh status`
3. Connect: `sudo ~/speedcam/cellular/connect-cellular-robust.sh`
4. Test: `sudo ~/speedcam/cellular/cellular-debug.sh test`
5. Start daemon: `sudo nohup ~/speedcam/cellular/auto-recover.sh 30 > ~/speedcam/cellular/auto-recover.log 2>&1 &`
6. Set up automation (optional): Create systemd services

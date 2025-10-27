#!/usr/bin/env python3
#
# Cellular Connection Monitor
#
# Monitors cellular connectivity by pinging a remote server at regular intervals.
# Detects connection failures, tracks downtime, and provides detailed diagnostics.
#
# Usage: sudo python3 monitor-cellular.py [options]
#
# Options:
#   --host HOST           Remote host to ping (default: 8.8.8.8)
#   --interval SECONDS    Ping interval in seconds (default: 10)
#   --timeout SECONDS     Ping timeout in seconds (default: 5)
#   --interface IFACE     Network interface to use (default: wwan0)
#   --duration MINUTES    Run for N minutes (default: 0 = infinite)
#

import subprocess
import time
import sys
import argparse
import socket
from datetime import datetime, timedelta
from collections import deque


class CellularMonitor:
    def __init__(self, host, interval, timeout, interface, duration):
        self.host = host
        self.interval = interval
        self.timeout = timeout
        self.interface = interface
        self.duration = duration
        
        self.start_time = None
        self.end_time = None
        self.ping_count = 0
        self.success_count = 0
        self.failure_count = 0
        self.downtime_start = None
        self.downtime_duration = 0
        self.max_downtime = 0
        self.current_downtime = 0
        
        # Track recent pings for statistics
        self.recent_pings = deque(maxlen=100)
        self.recent_failures = deque(maxlen=100)
        
    def log(self, level, message):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level:5s}] {message}")
        
    def check_interface(self):
        """Check if the interface exists and is up"""
        try:
            result = subprocess.run(
                ["ip", "link", "show", self.interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return False, "Interface not found"
            
            if "UP" not in result.stdout:
                return False, "Interface is DOWN"
            
            return True, "Interface is UP"
        except Exception as e:
            return False, f"Error checking interface: {e}"
    
    def check_ip_config(self):
        """Check if interface has IP address"""
        try:
            result = subprocess.run(
                ["ip", "addr", "show", self.interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return False, "Could not get IP config"
            
            # Look for inet or inet6 addresses
            if "inet " in result.stdout or "inet6 " in result.stdout:
                # Extract IP addresses
                lines = result.stdout.split('\n')
                ips = [line.strip() for line in lines if 'inet' in line]
                return True, f"IPs: {', '.join(ips[:2])}"
            else:
                return False, "No IP address assigned"
        except Exception as e:
            return False, f"Error checking IP: {e}"
    
    def check_dns(self):
        """Check if DNS is configured"""
        try:
            with open('/etc/resolv.conf', 'r') as f:
                content = f.read()
                nameservers = [line for line in content.split('\n') if line.startswith('nameserver')]
                if nameservers:
                    return True, f"DNS: {', '.join(nameservers[:2])}"
                else:
                    return False, "No nameservers in resolv.conf"
        except Exception as e:
            return False, f"Error reading resolv.conf: {e}"
    
    def check_route(self):
        """Check if default route exists"""
        try:
            result = subprocess.run(
                ["ip", "route", "show", "dev", self.interface],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return False, "No routes for interface"
            
            routes = result.stdout.strip().split('\n')
            if routes and routes[0]:
                return True, f"Routes: {len(routes)} found"
            else:
                return False, "No routes configured"
        except Exception as e:
            return False, f"Error checking routes: {e}"
    
    def check_modem_status(self):
        """Check modem status via mmcli"""
        try:
            result = subprocess.run(
                ["mmcli", "-L"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return False, "ModemManager not responding"
            
            if "Modem" in result.stdout:
                # Extract modem info
                lines = result.stdout.strip().split('\n')
                return True, f"Modem: {lines[0] if lines else 'Found'}"
            else:
                return False, "No modems found"
        except Exception as e:
            return False, f"Error checking modem: {e}"
    
    def resolve_hostname(self, hostname):
        """Resolve hostname to IP address"""
        try:
            ip = socket.gethostbyname(hostname)
            return True, ip
        except socket.gaierror as e:
            return False, str(e)
        except Exception as e:
            return False, str(e)
    
    def get_signal_strength(self):
        """Get current signal strength"""
        try:
            result = subprocess.run(
                ["mmcli", "-m", "0"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'signal quality' in line.lower():
                        signal = line.split(':')[-1].strip()
                        return signal
            return "unknown"
        except Exception:
            return "unknown"
    
    def ping_host(self):
        """Ping the remote host"""
        try:
            # First, check if host is an IP or hostname
            is_ip = False
            try:
                socket.inet_aton(self.host)
                is_ip = True
            except socket.error:
                pass
            
            # If hostname, try to resolve it first
            if not is_ip:
                dns_ok, resolved_ip = self.resolve_hostname(self.host)
                if not dns_ok:
                    return False, None, f"DNS resolution failed: {resolved_ip}"
                ping_target = resolved_ip
            else:
                ping_target = self.host
            
            cmd = [
                "ping",
                "-I", self.interface,
                "-c", "1",
                "-W", str(self.timeout),
                ping_target
            ]
            
            start = time.time()
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.timeout + 2
            )
            elapsed = time.time() - start
            
            if result.returncode == 0:
                # Extract RTT from output
                for line in result.stdout.split('\n'):
                    if 'time=' in line:
                        try:
                            rtt = float(line.split('time=')[1].split(' ')[0])
                            return True, rtt, None
                        except:
                            pass
                return True, elapsed * 1000, None
            else:
                # Ping failed
                error = result.stderr.strip() if result.stderr else "Ping failed"
                return False, None, error
        except subprocess.TimeoutExpired:
            return False, None, "Ping timeout"
        except Exception as e:
            return False, None, str(e)
    
    def run_diagnostics(self):
        """Run full diagnostics"""
        self.log("INFO", "Running diagnostics...")
        
        checks = [
            ("Interface", self.check_interface),
            ("IP Config", self.check_ip_config),
            ("DNS", self.check_dns),
            ("Routes", self.check_route),
            ("Modem", self.check_modem_status),
        ]
        
        for name, check_func in checks:
            success, message = check_func()
            level = "OK  " if success else "FAIL"
            self.log(level, f"{name:15s}: {message}")
    
    def monitor(self):
        """Main monitoring loop"""
        self.start_time = datetime.now()
        if self.duration:
            self.end_time = self.start_time + timedelta(minutes=self.duration)
        
        self.log("INFO", f"Starting cellular monitor")
        self.log("INFO", f"Host: {self.host}")
        self.log("INFO", f"Interface: {self.interface}")
        self.log("INFO", f"Interval: {self.interval}s")
        self.log("INFO", f"Timeout: {self.timeout}s")
        if self.duration:
            self.log("INFO", f"Duration: {self.duration} minutes")
        else:
            self.log("INFO", f"Duration: Infinite (Ctrl+C to stop)")
        
        # Initial diagnostics
        self.run_diagnostics()
        self.log("INFO", "Starting ping loop...")
        print()
        
        try:
            while True:
                # Check if duration exceeded
                if self.end_time and datetime.now() >= self.end_time:
                    self.log("INFO", "Duration exceeded, stopping")
                    break
                
                self.ping_count += 1
                success, rtt, error = self.ping_host()
                
                if success:
                    self.success_count += 1
                    self.recent_pings.append(rtt)
                    
                    # If we were in downtime, log recovery
                    if self.downtime_start:
                        downtime = (datetime.now() - self.downtime_start).total_seconds()
                        self.downtime_duration += downtime
                        if downtime > self.max_downtime:
                            self.max_downtime = downtime
                        
                        self.log("INFO", f"✓ Connection RECOVERED after {downtime:.1f}s downtime")
                        self.downtime_start = None
                        self.current_downtime = 0
                    
                    self.log("OK  ", f"Ping #{self.ping_count}: {rtt:.1f}ms")
                else:
                    self.failure_count += 1
                    self.recent_failures.append(error)
                    
                    # Get signal strength at time of failure
                    signal = self.get_signal_strength()
                    
                    # Track downtime
                    if not self.downtime_start:
                        self.downtime_start = datetime.now()
                        self.log("FAIL", f"✗ Ping loss #{self.failure_count}: {error} (Signal: {signal})")
                    else:
                        self.current_downtime = (datetime.now() - self.downtime_start).total_seconds()
                        self.log("FAIL", f"✗ Still down for {self.current_downtime:.1f}s (Losses: {self.failure_count}, Signal: {signal}): {error}")
                
                # Print stats every 10 pings
                if self.ping_count % 10 == 0:
                    self.print_stats()
                
                time.sleep(self.interval)
        
        except KeyboardInterrupt:
            self.log("INFO", "Interrupted by user")
        
        finally:
            self.print_final_stats()
    
    def print_stats(self):
        """Print current statistics"""
        success_rate = (self.success_count / self.ping_count * 100) if self.ping_count > 0 else 0
        
        stats = f"Stats: {self.success_count}/{self.ping_count} ({success_rate:.1f}%)"
        
        if self.recent_pings:
            avg_rtt = sum(self.recent_pings) / len(self.recent_pings)
            min_rtt = min(self.recent_pings)
            max_rtt = max(self.recent_pings)
            stats += f" | RTT: {avg_rtt:.1f}ms (min: {min_rtt:.1f}ms, max: {max_rtt:.1f}ms)"
        
        if self.downtime_start:
            stats += f" | DOWNTIME: {self.current_downtime:.1f}s"
        
        self.log("STAT", stats)
    
    def print_final_stats(self):
        """Print final statistics"""
        elapsed = (datetime.now() - self.start_time).total_seconds()
        success_rate = (self.success_count / self.ping_count * 100) if self.ping_count > 0 else 0
        loss_rate = (self.failure_count / self.ping_count * 100) if self.ping_count > 0 else 0
        
        print()
        print("=" * 70)
        self.log("INFO", "FINAL STATISTICS")
        print("=" * 70)
        
        self.log("INFO", f"Total pings: {self.ping_count}")
        self.log("INFO", f"Successful: {self.success_count}")
        self.log("INFO", f"Failed (Cumulative losses): {self.failure_count}")
        self.log("INFO", f"Success rate: {success_rate:.1f}%")
        self.log("INFO", f"Loss rate: {loss_rate:.1f}%")
        self.log("INFO", f"Total time: {elapsed:.1f}s ({elapsed/60:.1f} minutes)")
        
        if self.recent_pings:
            avg_rtt = sum(self.recent_pings) / len(self.recent_pings)
            min_rtt = min(self.recent_pings)
            max_rtt = max(self.recent_pings)
            self.log("INFO", f"RTT - Avg: {avg_rtt:.1f}ms, Min: {min_rtt:.1f}ms, Max: {max_rtt:.1f}ms")
        
        if self.failure_count > 0:
            self.log("WARN", f"Total downtime: {self.downtime_duration:.1f}s")
            self.log("WARN", f"Max downtime episode: {self.max_downtime:.1f}s")
            self.log("WARN", f"Cumulative ping losses: {self.failure_count}")
            
            if self.recent_failures:
                failure_types = {}
                for failure in self.recent_failures:
                    failure_types[failure] = failure_types.get(failure, 0) + 1
                
                self.log("WARN", "Failure breakdown:")
                for failure_type, count in sorted(failure_types.items(), key=lambda x: x[1], reverse=True):
                    self.log("WARN", f"  - {failure_type}: {count} times")
        
        print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Monitor cellular connectivity with diagnostics"
    )
    parser.add_argument("--host", default="8.8.8.8", help="Remote host to ping (default: 8.8.8.8)")
    parser.add_argument("--interval", type=int, default=10, help="Ping interval in seconds (default: 10)")
    parser.add_argument("--timeout", type=int, default=5, help="Ping timeout in seconds (default: 5)")
    parser.add_argument("--interface", default="wwan0", help="Network interface to use (default: wwan0)")
    parser.add_argument("--duration", type=int, default=0, help="Run for N minutes (default: 0 = infinite)")
    
    args = parser.parse_args()
    
    # Check if running as root
    if subprocess.os.geteuid() != 0:
        print("ERROR: This script must be run as root (use sudo)")
        sys.exit(1)
    
    monitor = CellularMonitor(
        host=args.host,
        interval=args.interval,
        timeout=args.timeout,
        interface=args.interface,
        duration=args.duration
    )
    
    monitor.monitor()


if __name__ == "__main__":
    main()

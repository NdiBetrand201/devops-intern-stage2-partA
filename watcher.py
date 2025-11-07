
"""
Nginx Log Watcher for Blue/Green Deployment Observability
Monitors Nginx access logs and sends Slack alerts on:
1. Failover events (pool changes)
2. High error rates (5xx errors exceed threshold)
"""

import os
import sys
import time
import json
import requests
import io
from collections import deque
from datetime import datetime


class LogWatcher:
    def __init__(self):
        # Load configuration from environment
        self.slack_webhook = os.getenv('SLACK_WEBHOOK_URL')
        self.error_threshold = float(os.getenv('ERROR_RATE_THRESHOLD', '2.0'))
        self.window_size = int(os.getenv('WINDOW_SIZE', '200'))
        self.cooldown = int(os.getenv('ALERT_COOLDOWN_SEC', '300'))
        self.log_path = os.getenv('NGINX_LOG_PATH', '/var/log/nginx/access.log')
        self.read_existing = os.getenv('READ_EXISTING_LOGS', 'true').lower() == 'true'
        
        # State tracking
        self.last_pool = None
        self.request_window = deque(maxlen=self.window_size)
        self.last_failover_alert = 0
        self.last_error_alert = 0
        self.maintenance_mode = os.getenv('MAINTENANCE_MODE', 'false').lower() == 'true'
        
        # Validate configuration
        if not self.slack_webhook:
            print("ERROR: SLACK_WEBHOOK_URL not set in environment")
            sys.exit(1)
        
        print(f"📊 Log Watcher Started")
        print(f"   Log Path: {self.log_path}")
        print(f"   Error Threshold: {self.error_threshold}%")
        print(f"   Window Size: {self.window_size} requests")
        print(f"   Alert Cooldown: {self.cooldown}s")
        print(f"   Maintenance Mode: {self.maintenance_mode}")
        print(f"   Read Existing Logs: {self.read_existing}")
        print()

    def send_slack_alert(self, title, message, color="warning", fields=None):
        """Send formatted alert to Slack"""
        if self.maintenance_mode:
            print(f"🔇 Alert suppressed (maintenance mode): {title}")
            return
        
        payload = {
            "attachments": [{
                "color": color,
                "title": title,
                "text": message,
                "footer": "Backend.im Alert System",
                "ts": int(time.time())
            }]
        }
        
        if fields:
            payload["attachments"][0]["fields"] = fields
        
        try:
            response = requests.post(
                self.slack_webhook,
                json=payload,
                timeout=5
            )
            if response.status_code == 200:
                print(f"✅ Alert sent: {title}")
            else:
                print(f"❌ Slack error: {response.status_code}")
        except Exception as e:
            print(f"❌ Failed to send alert: {e}")



    def check_failover(self, pool):
        """Detect and alert on failover events"""
        if self.last_pool is None:
            
            self.last_pool = pool
            print(f"🔵 Initial pool: {pool}")
            return
        
        if pool != self.last_pool:
        
            now = time.time()
            if now - self.last_failover_alert > self.cooldown:
                print(f"🚨 FAILOVER: {self.last_pool} → {pool}")
                
                self.send_slack_alert(
                    title="🔄 Failover Detected",
                    message=f"Traffic switched from *{self.last_pool}* to *{pool}*",
                    color="warning",
                    fields=[
                        {"title": "Previous Pool", "value": self.last_pool, "short": True},
                        {"title": "Current Pool", "value": pool, "short": True},
                        {"title": "Timestamp", "value": datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "short": False}
                    ]
                )
                
                self.last_failover_alert = now
            
            self.last_pool = pool

    def check_error_rate(self):
        """Calculate error rate and alert if threshold exceeded"""
        if len(self.request_window) < 10:
            
            return
        
        error_count = sum(1 for status in self.request_window if status >= 500)
        total = len(self.request_window)
        error_rate = (error_count / total) * 100
        
        if error_rate > self.error_threshold:
            now = time.time()
            if now - self.last_error_alert > self.cooldown:
                print(f"🚨 HIGH ERROR RATE: {error_rate:.1f}%")
                
                self.send_slack_alert(
                    title="⚠️ High Error Rate Detected",
                    message=f"Error rate is *{error_rate:.1f}%* (threshold: {self.error_threshold}%)",
                    color="danger",
                    fields=[
                        {"title": "Error Count", "value": f"{error_count}/{total} requests", "short": True},
                        {"title": "Error Rate", "value": f"{error_rate:.1f}%", "short": True},
                        {"title": "Window Size", "value": f"{self.window_size} requests", "short": True},
                        {"title": "Current Pool", "value": self.last_pool or "unknown", "short": True}
                    ]
                )
                
                self.last_error_alert = now

    def parse_log_line(self, line):
        """Parse JSON log line"""
        try:
            return json.loads(line.strip())
        except json.JSONDecodeError:
            return None

    def process_log_entry(self, entry):
        """Process a single log entry"""
        pool = entry.get('pool', 'unknown')
        status = entry.get('status', 0)
        upstream_status = entry.get('upstream_status', '-')
        request_time = entry.get('request_time', 0)
        request = entry.get('request', '-')

        
        if pool in ['unknown', '-', '', None]:
            return
        try:
            status = int(status)
        except (ValueError, TypeError):
            status = 0

        # Display log entry
        timestamp = datetime.now().strftime('%H:%M:%S')
        if status < 400:
            status_emoji = "✅"
        elif status < 500:
            status_emoji = "⚠️"
        else:
            status_emoji = "❌"

        print(f"{status_emoji} [{timestamp}] "
              f"Pool: {pool:5s} | "
              f"Status: {status} | "
              f"Upstream: {upstream_status:3s} | "
              f"Time: {request_time}s | "
              f"Request: {request[:50]}")

        # Update tracking
        self.request_window.append(status)
        self.check_failover(pool)
        self.check_error_rate()

    def tail_log(self):
        """Tail the log file and process entries"""
        print(f"📂 Watching: {self.log_path}")

        # Wait for file to exist
        while not os.path.exists(self.log_path):
            print(f"⏳ Waiting for log file: {self.log_path}")
            time.sleep(2)

        # Wait for first content
        max_wait = 30
        wait_time = 0
        while os.path.getsize(self.log_path) == 0 and wait_time < max_wait:
            print(f"⏳ Log file empty. Waiting for first entry... ({wait_time}s)")
            time.sleep(2)
            wait_time += 2

        if os.path.getsize(self.log_path) == 0:
            print("⚠️  Log file still empty after 30s, but continuing to monitor...")

        print("✅ Log file ready! Starting monitoring...\n")

        with open(self.log_path, 'r', buffering=1) as f:
            # Read existing logs if enabled
            if self.read_existing and os.path.getsize(self.log_path) > 0:
                print("📖 Reading existing log entries...")
                line_count = 0
                for line in f:
                    entry = self.parse_log_line(line)
                    if entry:
                        self.process_log_entry(entry)
                        line_count += 1
                print(f"✅ Processed {line_count} existing entries\n")
                print("👀 Now monitoring for new entries...\n")
            else:
                # Seek to end for new entries only
                try:
                    f.seek(0, 2)
                    print("⏩ Skipped to end. Monitoring new entries only...\n")
                except (io.UnsupportedOperation, OSError):
                    print("⚠️  Seek not supported. Starting from current position.\n")

            # Monitor new entries
            while True:
                line = f.readline()
                if not line:
                    time.sleep(0.1)
                    continue

                entry = self.parse_log_line(line)
                if entry:
                    self.process_log_entry(entry)

    def run(self):
        """Main loop"""
        try:
            self.tail_log()
        except KeyboardInterrupt:
            print("\n👋 Shutting down gracefully...")
        except Exception as e:
            print(f"❌ Fatal error: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


if __name__ == '__main__':
    watcher = LogWatcher()
    watcher.run()
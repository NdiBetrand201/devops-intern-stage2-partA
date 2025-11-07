# Blue/Green Deployment with Nginx Auto-Failover + Observability

This project implements a Blue/Green deployment pattern with automatic failover, real-time monitoring, and Slack alerting.

## Features

### Stage 2: Auto-Failover
- ✅ **Zero-downtime failover**: Automatically switches from Blue to Green on failure
- ✅ **Fast failure detection**: 2-second timeouts ensure quick failover
- ✅ **Transparent to clients**: Clients always get 200 responses (no errors during failover)
- ✅ **Header forwarding**: App headers (X-App-Pool, X-Release-Id) are passed through

### Stage 3: Observability & Alerts (NEW)
- ✅ **Structured logging**: JSON-formatted logs with pool, status, and timing data
- ✅ **Real-time monitoring**: Python watcher tails logs continuously
- ✅ **Failover detection**: Alerts when traffic switches pools
- ✅ **Error rate monitoring**: Alerts when 5xx errors exceed threshold
- ✅ **Slack integration**: Automatic notifications to your channel
- ✅ **Alert cooldowns**: Prevents alert spam
- ✅ **Maintenance mode**: Suppress alerts during planned work

## Architecture
```
Client → Nginx (8080) → Blue App (8081) [Primary]
                     → Green App (8082) [Backup]
                     ↓
                  Logs (shared volume)
                     ↓
                  Log Watcher
                     ↓
                  Slack Alerts
```

## Prerequisites

- Docker (v20.x or higher)
- Docker Compose (v1.29.x or higher)
- Slack workspace with webhook access

## Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo-url>
cd blue-green-deployment

# Copy environment template
cp .env.example .env
```

### 2. Get Slack Webhook URL

1. Go to https://api.slack.com/messaging/webhooks
2. Create a new app
3. Enable Incoming Webhooks
4. Add webhook to workspace
5. Copy the webhook URL

### 3. Configure Environment

Edit `.env` file:
```bash
# Application images (from task)
BLUE_IMAGE=ghcr.io/hngdevops/stagerepo:blue-latest
GREEN_IMAGE=ghcr.io/hngdevops/stagerepo:green-latest

# Slack webhook URL (REQUIRED for Stage 3)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Alert configuration
ERROR_RATE_THRESHOLD=2.0
WINDOW_SIZE=200
ALERT_COOLDOWN_SEC=300
MAINTENANCE_MODE=false
```

### 4. Start Services
```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 5. Verify Deployment
```bash
# Test main endpoint
curl http://localhost:8080/version

# Should return:
# HTTP/1.1 200 OK
# X-App-Pool: blue
# X-Release-Id: v1.0-blue
```

## Testing

### Test 1: Normal Operation
```bash
# Make several requests
for i in {1..10}; do
  curl -s http://localhost:8080/version | jq '.status'
  sleep 0.5
done

# All should return "OK"
# Check logs show Blue is serving
docker logs alert_watcher --tail 20
```

### Test 2: Failover Detection
```bash
# 1. Trigger chaos on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error

# 2. Make a request (should get Green's response)
curl http://localhost:8080/version
# X-App-Pool: green

# 3. Check Slack for failover alert
# You should receive: "🔄 Failover Detected"

# 4. Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

### Test 3: Error Rate Alert
```bash
# 1. Generate errors
for i in {1..50}; do
  curl -X POST http://localhost:8081/chaos/start?mode=error
  curl http://localhost:8080/version
  sleep 0.1
done

# 2. Check Slack for error rate alert
# You should receive: "⚠️ High Error Rate Detected"

# 3. Clean up
curl -X POST http://localhost:8081/chaos/stop
```

### Test 4: Maintenance Mode
```bash
# 1. Enable maintenance mode
# Edit .env: MAINTENANCE_MODE=true
docker-compose restart alert_watcher

# 2. Trigger chaos (no alerts should be sent)
curl -X POST http://localhost:8081/chaos/start?mode=error
curl http://localhost:8080/version

# 3. Disable maintenance mode
# Edit .env: MAINTENANCE_MODE=false
docker-compose restart alert_watcher

# 4. Clean up
curl -X POST http://localhost:8081/chaos/stop
```

## Monitoring

### View Live Logs
```bash
# All services
docker-compose logs -f

# Watcher only
docker logs -f alert_watcher

# Nginx logs (JSON format)
docker exec nginx_proxy tail -f /var/log/nginx/access.log
```

### Check Service Health
```bash
# Container status
docker-compose ps

# Direct health checks
curl http://localhost:8081/healthz  # Blue
curl http://localhost:8082/healthz  # Green
curl http://localhost:8080/version  # Via Nginx
```

### View Metrics
```bash
# Resource usage
docker stats

# Watcher status
docker logs alert_watcher --tail 50
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| **Stage 2 Variables** |||
| BLUE_IMAGE | (required) | Docker image for Blue app |
| GREEN_IMAGE | (required) | Docker image for Green app |
| ACTIVE_POOL | blue | Initial active pool |
| RELEASE_ID_BLUE | v1.0-blue | Blue release identifier |
| RELEASE_ID_GREEN | v1.0-green | Green release identifier |
| PORT | 3000 | App listen port |
| **Stage 3 Variables** |||
| SLACK_WEBHOOK_URL | (required) | Slack incoming webhook URL |
| ERROR_RATE_THRESHOLD | 2.0 | Error rate alert threshold (%) |
| WINDOW_SIZE | 200 | Sliding window size (requests) |
| ALERT_COOLDOWN_SEC | 300 | Cooldown between alerts (seconds) |
| MAINTENANCE_MODE | false | Suppress alerts when true |

### Nginx Configuration

Key settings in `nginx.conf.template`:
```nginx
# Custom log format with observability data
log_format observability '{...JSON...}';

# Fast failover timeouts
proxy_connect_timeout 2s;
proxy_read_timeout 2s;

# Retry logic
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
```

## Alert Types

### 🔄 Failover Detected

**Trigger:** Pool switches (Blue → Green or Green → Blue)

**Response:** Check logs of failed pool, investigate cause

**Example:**
```
🔄 Failover Detected
Traffic switched from blue to green

Previous Pool: blue
Current Pool: green
```

### ⚠️ High Error Rate Detected

**Trigger:** 5xx error rate exceeds ERROR_RATE_THRESHOLD

**Response:** Check application logs, verify dependencies

**Example:**
```
⚠️ High Error Rate Detected
Error rate is 8.5% (threshold: 2.0%)

Error Count: 17/200 requests
Current Pool: blue
```

See [runbook.md](runbook.md) for detailed alert response procedures.

## Troubleshooting

### No Slack alerts received
```bash
# Check watcher is running
docker-compose ps | grep alert_watcher

# Check watcher logs
docker logs alert_watcher

# Verify webhook URL
docker-compose exec alert_watcher env | grep SLACK_WEBHOOK_URL

# Test webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert"}' \
  $SLACK_WEBHOOK_URL
```

### Watcher not detecting events
```bash
# Check if logs are being written
docker exec nginx_proxy ls -lh /var/log/nginx/access.log

# Check if watcher can read logs
docker exec alert_watcher cat /var/log/nginx/access.log | tail -5

# Verify log format is JSON
docker exec nginx_proxy tail -1 /var/log/nginx/access.log
```

### False positive alerts
```bash
# Increase threshold or window size
# Edit .env:
ERROR_RATE_THRESHOLD=5.0
WINDOW_SIZE=500

# Restart watcher
docker-compose restart alert_watcher
```

## Project Structure
```
blue-green-deployment/
├── docker-compose.yml          # Service orchestration
├── nginx.conf.template         # Nginx configuration
├── watcher.py                  # Log monitoring script
├── Dockerfile.watcher          # Watcher container image
├── requirements.txt            # Python dependencies
├── .env                        # Environment variables (gitignored)
├── .env.example                # Environment template
├── README.md                   # This file
├── runbook.md                  # Alert response guide
├── DECISION.md                 # Implementation decisions
└── test.sh                     # Automated tests
```

## Screenshots

### Failover Alert
![Failover Alert](screenshots/failover-alert.png)

### High Error Rate Alert
![Error Rate Alert](screenshots/error-rate-alert.png)

### Container Logs
![Container Logs](screenshots/container-logs.png)

## Cleanup
```bash
# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v

# Remove images (optional)
docker-compose down --rmi all
```

## License

MIT

## Author

Ndi Betrand Teku
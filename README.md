# Blue/Green Deployment with Nginx Auto-Failover

This project implements a Blue/Green deployment pattern with automatic failover using Nginx as a reverse proxy.

## Architecture
```
Client → Nginx (8080) → Blue App (8081) [Primary]
                     → Green App (8082) [Backup]
```

## Features

- **Zero-downtime failover**: Automatically switches from Blue to Green on failure
- **Fast failure detection**: 2-second timeouts ensure quick failover
- **Transparent to clients**: Clients always get 200 responses (no errors during failover)
- **Header forwarding**: App headers (X-App-Pool, X-Release-Id) are passed through
- **Direct chaos endpoints**: Blue/Green apps exposed for testing

## Prerequisites

- Docker (v20.x or higher)
- Docker Compose (v1.29.x or higher)

## Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd blue-green-deployment

# Copy environment template
cp .env.example .env

# Edit .env with your values
nano .env  # or your preferred editor
```

### 2. Configure Environment

Edit `.env` file:
```bash
# Replace these with actual image URLs from task
BLUE_IMAGE=ghcr.io/your-blue-image
GREEN_IMAGE=ghcr.io/your-green-image

# Other settings (usually don't need to change)
ACTIVE_POOL=blue
RELEASE_ID_BLUE=v1.0.0-blue
RELEASE_ID_GREEN=v1.0.0-green
PORT=3000
```

### 3. Start Services
```bash
# Start all services in background
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 4. Test the Deployment

#### Normal State (Blue Active)
```bash
# Should return Blue's version
curl http://localhost:8080/version

# Expected response:
# {
#   "version": "...",
#   "pool": "blue"
# }
# Headers: X-App-Pool: blue, X-Release-Id: v1.0.0-blue
```

#### Induce Failure
```bash
# Make Blue start failing
curl -X POST http://localhost:8081/chaos/start?mode=error

# Immediately test - should get Green's response
curl http://localhost:8080/version

# Expected: X-App-Pool: green
```

#### Stop Chaos
```bash
# Stop Blue's failure mode
curl -X POST http://localhost:8081/chaos/stop

# Wait 10 seconds for recovery
sleep 10

# Should go back to Blue
curl http://localhost:8080/version
```

## Available Endpoints

### Through Nginx (Port 8080)
- `GET http://localhost:8080/version` - Get version info
- `GET http://localhost:8080/healthz` - Health check

### Direct Blue Access (Port 8081)
- `GET http://localhost:8081/version` - Blue version
- `GET http://localhost:8081/healthz` - Blue health
- `POST http://localhost:8081/chaos/start?mode=error` - Start error mode
- `POST http://localhost:8081/chaos/start?mode=timeout` - Start timeout mode
- `POST http://localhost:8081/chaos/stop` - Stop chaos

### Direct Green Access (Port 8082)
- Same endpoints as Blue, but on port 8082

## Testing

Run the automated test script:
```bash
./test.sh
```

This will:
1. Check all services are up
2. Verify Blue is active
3. Test consistency (10 requests)
4. Induce failure on Blue
5. Verify failover to Green
6. Test stability (20 requests, no errors)

## Troubleshooting

### Services won't start
```bash
# Check logs
docker-compose logs

# Check specific service
docker-compose logs app_blue
docker-compose logs nginx
```

### Failover not working
```bash
# Check nginx config
docker exec nginx_proxy cat /etc/nginx/nginx.conf

# Check nginx error logs
docker logs nginx_proxy

# Test direct access to apps
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz
```

### Headers not showing
```bash
# Use -i flag to see headers
curl -i http://localhost:8080/version

# Check if nginx is passing headers
docker exec nginx_proxy cat /etc/nginx/nginx.conf | grep proxy_pass_header
```

## Cleanup
```bash
# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v

# Remove images (optional)
docker-compose down --rmi all
```

## Configuration Files

- `docker-compose.yml` - Service orchestration
- `nginx.conf.template` - Nginx configuration
- `.env` - Environment variables
- `test.sh` - Automated tests

## Key Configuration Details

### Nginx Upstream
```nginx
upstream backend {
    server app_blue:3000 max_fails=1 fail_timeout=10s;
    server app_green:3000 backup;
    keepalive 32;
}
```

- `max_fails=1` - Mark as down after 1 failure
- `fail_timeout=10s` - Try again after 10 seconds
- `backup` - Green only used when Blue is down

### Timeouts

- `proxy_connect_timeout: 2s` - Connection timeout
- `proxy_read_timeout: 2s` - Response timeout
- `proxy_next_upstream_timeout: 5s` - Total retry time

These ensure fast failover (<3 seconds).

## License

MIT

## Author

Ndi Betrand Teku
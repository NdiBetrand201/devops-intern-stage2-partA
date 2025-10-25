# devops-intern-stage2-partA# Blue/Green Node.js Deployment with Nginx Auto-Failover

This setup deploys two identical Node.js services (Blue and Green) behind Nginx for zero-downtime failover using `yimikaade/wonderful:devops-stage-two`. Blue is primary by default; traffic fails over to Green on errors/timeouts/5xx without client-visible failures.

## Prerequisites
- Docker and Docker Compose installed.
- Access to `yimikaade/wonderful:devops-stage-two` images.

## Setup
1. Copy `.env.example` to `.env` and verify values:
   - `BLUE_IMAGE` and `GREEN_IMAGE`: Set to `yimikaade/wonderful:devops-stage-two`.
   - `ACTIVE_POOL`: `blue` (default) or `green`.
   - `RELEASE_ID_BLUE` and `RELEASE_ID_GREEN`: For `X-Release-Id` headers.
   - `PORT`: Nginx port (default 8080).
2. Make `start.sh` executable:
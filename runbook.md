# Backend.im Runbook - Alert Response Guide

## Overview

This runbook describes what each alert means and how operators should respond.

---

## Alert Types

### 1. 🔄 Failover Detected

**What It Means:**
Traffic has switched from one pool (Blue/Green) to another. This indicates:
- The primary pool has failed health checks
- Nginx automatically routed traffic to the backup pool
- The system is still operational (zero downtime)

**Alert Example:**
```
🔄 Failover Detected
Traffic switched from blue to green

Previous Pool: blue
Current Pool: green
Direction: blue → green
Timestamp: 2025-10-25 14:30:45
```

**Severity:** ⚠️ Warning (system still working, but investigation needed)

**Immediate Actions:**
1. **Verify the failover is real** (not a test):
```bash
   # Check if MAINTENANCE_MODE is false
   docker-compose exec alert_watcher env | grep MAINTENANCE_MODE
```

2. **Check logs of the failed pool:**
```bash
   # If Blue failed
   docker logs app_blue --tail 50
   
   # If Green failed
   docker logs app_green --tail 50
```

3. **Check health status:**
```bash
   # Blue health
   curl http://localhost:8081/healthz
   
   # Green health
   curl http://localhost:8082/healthz
```

4. **Check container status:**
```bash
   docker-compose ps
```

**Common Causes:**
- Application crash or hang
- Memory exhaustion (OOM)
- Database connection failure
- Dependency service down
- Code bug causing errors

**Resolution Steps:**

**If the failed pool is down:**
```bash
# Restart the failed container
docker-compose restart app_blue  # or app_green

# Watch logs during restart
docker logs -f app_blue
```

**If the failed pool is running but unhealthy:**
```bash
# 1. Check application logs for errors
docker logs app_blue --tail 100

# 2. Check resource usage
docker stats app_blue --no-stream

# 3. Test the endpoint directly
curl -v http://localhost:8081/version
```

**Post-Incident:**
- Document what caused the failure
- Update monitoring thresholds if needed
- Consider if code changes are required

**When to Escalate:**
- Both pools are failing
- Repeated failovers (flip-flopping)
- Unknown cause after 15 minutes of investigation

---

### 2. ⚠️ High Error Rate Detected

**What It Means:**
The backend is returning too many 5xx errors. This indicates:
- Application is struggling or misconfigured
- Database or dependency issues
- Resource exhaustion
- Code bug affecting multiple requests

**Alert Example:**
```
⚠️ High Error Rate Detected
Error rate is 8.5% over the last 200 requests.
Threshold: 2.0%

Error Count: 17/200 requests
Error Rate: 8.5%
Threshold: 2.0%
Current Pool: blue
Window Size: 200 requests
```

**Severity:** 🚨 Critical (users are experiencing errors)

**Immediate Actions:**

1. **Check current error rate:**
```bash
   # View recent nginx logs
   docker logs nginx_proxy --tail 50 | grep '"status":5'
```

2. **Identify which pool is affected:**
```bash
   # Check both pools
   curl http://localhost:8081/version  # Blue
   curl http://localhost:8082/version  # Green
```

3. **Check application logs:**
```bash
   # Current active pool logs
   docker logs app_blue --tail 100 | grep -i error
```

4. **Check resource usage:**
```bash
   docker stats --no-stream
```

**Common Causes:**
- **Database connection pool exhausted**
  - Symptom: "connection refused" or timeouts
  - Fix: Restart affected container
  
- **Memory leak / OOM**
  - Symptom: Container restarting frequently
  - Fix: Increase memory limit or fix leak
  
- **Dependency service down**
  - Symptom: Consistent errors to specific endpoint
  - Fix: Check and restart dependency
  
- **Code bug**
  - Symptom: Errors after recent deployment
  - Fix: Rollback or hotfix

**Resolution Steps:**

**Quick mitigation (if one pool is healthy):**
```bash
# Stop the unhealthy pool to force traffic to healthy one
docker stop app_blue  # or app_green

# Or restart the unhealthy pool
docker-compose restart app_blue
```

**If both pools are affected:**
```bash
# 1. Check if it's a deployment issue
# Rollback to previous version if needed

# 2. Check dependencies
docker-compose ps

# 3. Check logs for specific error patterns
docker logs app_blue 2>&1 | grep -A 5 "error"
```

**Testing after fix:**
```bash
# Generate some test traffic
for i in {1..20}; do
  curl http://localhost:8080/version
  sleep 0.5
done

# Check if errors stopped
docker logs alert_watcher --tail 20
```

**Post-Incident:**
- Review error logs to find root cause
- Add monitoring for the specific failure mode
- Consider adjusting ERROR_RATE_THRESHOLD if too sensitive

**When to Escalate:**
- Error rate > 50% for more than 5 minutes
- Unable to identify cause within 10 minutes
- Both pools are failing
- Errors affecting production users

---

### 3. ✅ Recovery Detected (Informational)

**What It Means:**
The primary pool has recovered and is serving traffic again.

**Actions:**
- Review what caused the initial failure
- Document in incident log
- No immediate action required

---

## Suppressing Alerts During Maintenance

When performing planned work (deployments, testing, chaos drills), suppress alerts:

**Before maintenance:**
```bash
# Edit .env file
nano .env

# Set maintenance mode to true
MAINTENANCE_MODE=true

# Restart watcher
docker-compose restart alert_watcher
```

**After maintenance:**
```bash
# Edit .env file
nano .env

# Set maintenance mode to false
MAINTENANCE_MODE=false

# Restart watcher
docker-compose restart alert_watcher
```

---

## Manual Failover Testing

To test failover manually:
```bash
# 1. Enable maintenance mode (suppress alerts)
# Edit .env: MAINTENANCE_MODE=true
docker-compose restart alert_watcher

# 2. Trigger chaos on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error

# 3. Watch traffic switch to Green
curl http://localhost:8080/version
# Should show: "pool": "green"

# 4. Stop chaos
curl -X POST http://localhost:8081/chaos/stop

# 5. Wait for recovery
sleep 15

# 6. Disable maintenance mode
# Edit .env: MAINTENANCE_MODE=false
docker-compose restart alert_watcher
```

---

## Monitoring Commands

**View live logs:**
```bash
# All services
docker-compose logs -f

# Specific service
docker logs -f alert_watcher
docker logs -f nginx_proxy
docker logs -f app_blue
```

**Check service health:**
```bash
# All containers
docker-compose ps

# Specific health checks
curl http://localhost:8080/version
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz
```

**View recent nginx logs:**
```bash
docker exec nginx_proxy tail -f /var/log/nginx/access.log
```

**Check watcher status:**
```bash
docker logs alert_watcher --tail 50
```

**Resource usage:**
```bash
docker stats
```

---

## Alert Thresholds

Current configuration (defined in .env):

| Setting | Default | Description |
|---------|---------|-------------|
| ERROR_RATE_THRESHOLD | 2.0% | Alert when 5xx rate exceeds this |
| WINDOW_SIZE | 200 requests | Sliding window size |
| ALERT_COOLDOWN_SEC | 300 seconds (5 min) | Time between similar alerts |

**Adjusting thresholds:**

If you get too many false alarms:
```bash
# Increase threshold or window size
ERROR_RATE_THRESHOLD=5.0
WINDOW_SIZE=500
```

If you want faster detection:
```bash
# Decrease threshold or window size
ERROR_RATE_THRESHOLD=1.0
WINDOW_SIZE=100
```

---

## Escalation Path

| Severity | Response Time | Escalate If |
|----------|---------------|-------------|
| Info | No action needed | N/A |
| Warning | 15 minutes | Can't resolve in 15 min |
| Critical | Immediate | Can't resolve in 10 min or both pools down |

**Escalation contacts:**
- On-call engineer: [Your contact info]
- Team lead: [Team lead contact]
- Infrastructure team: [Infra contact]

---

## Common Scenarios

### Scenario 1: Blue fails, Green takes over
```
Timeline:
10:30:00 - Blue becomes unhealthy
10:30:05 - Nginx detects failure, routes to Green
10:30:06 - Alert sent: "Failover Detected"

Response:
1. Check Blue logs
2. Identify root cause
3. Fix and restart Blue
4. Blue recovers, traffic returns
```

### Scenario 2: High error rate on both pools
```
Timeline:
11:00:00 - Database connection pool exhausted
11:00:10 - Both Blue and Green start returning 500 errors
11:00:15 - Alert sent: "High Error Rate"

Response:
1. Identify it's affecting both pools
2. Check dependencies (database, redis, etc.)
3. Restart database or increase connection pool
4. Errors stop, traffic recovers
```

### Scenario 3: False alarm during load testing
```
Timeline:
14:00:00 - Load test starts
14:00:30 - Intentional errors generated
14:00:35 - Alert sent: "High Error Rate"

Response:
1. Verify it's expected (load test in progress)
2. Next time, enable MAINTENANCE_MODE=true before testing
3. No action needed
```

---

## Additional Resources

- [Stage 2 README](README.md) - Full system documentation
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Slack Webhooks Guide](https://api.slack.com/messaging/webhooks)

---

## Incident Log Template

After resolving an incident, document it:
```markdown
## Incident: [Date] [Time]

**Alert:** Failover Detected / High Error Rate
**Duration:** [Start] - [End]
**Severity:** Warning / Critical
**Affected Pool:** Blue / Green / Both

**Root Cause:**
[What caused the issue]

**Resolution:**
[What was done to fix it]

**Prevention:**
[What can be done to prevent recurrence]

**Lessons Learned:**
[What we learned]
```

---

## Questions?

If this runbook doesn't cover your scenario:
1. Check logs: `docker-compose logs`
2. Review metrics: `docker stats`
3. Consult team documentation
4. Escalate to on-call engineer
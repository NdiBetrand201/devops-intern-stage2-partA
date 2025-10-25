# Implementation Decisions

## Upstream Configuration
- **max_fails=1 fail_timeout=5s**: Detects failures quickly while avoiding transient flaps.
- **backup directive**: Ensures Green only serves traffic when Blue fails.
- **proxy_next_upstream**: Retries on error/timeout/5xx within the same request for zero client failures.

## Timeouts
- Connect (1s) + send/read (3s) + next upstream (3s) < 10s to meet stability requirements.
- `proxy_next_upstream_timeout 3s` aligns with read timeout for consistency.

## Templating
- `start.sh` over envsubst: Handles conditional logic for `ACTIVE_POOL`.
- Supports `nginx -s reload` for config updates; full toggle requires restart for env changes.

## Healthchecks
- `/healthz` ensures app readiness via Docker Compose `depends_on`.

## Assumptions
- Apps listen on port 80 (update to 3000 if needed).
- Images (`yimikaade/wonderful:devops-stage-two`) provide `/version`, `/chaos/*`, `/healthz`.
- No TLS/auth required (HTTP only).

This setup ensures zero failed requests, correct header forwarding, and CI parameterization.
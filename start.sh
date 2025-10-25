#!/bin/sh

set -e  # Exit on errors

# Determine primary and backup based on ACTIVE_POOL
if [ "$ACTIVE_POOL" = "blue" ]; then
  PRIMARY="app_blue:80"
  BACKUP="app_green:80"
  APP_POOL="blue"
else
  PRIMARY="app_green:80"
  BACKUP="app_blue:80"
  APP_POOL="green"
fi

# Generate nginx.conf dynamically
cat > /etc/nginx/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream primary {
        server ${PRIMARY} max_fails=1 fail_timeout=5s;
    }

    upstream backup {
        server ${BACKUP} backup;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://primary;

            # Retry on errors, timeouts, and 5xx for zero failed requests
            proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
            proxy_next_upstream_tries 1;  # Try backup once
            proxy_next_upstream_timeout 3s;

            # Tight timeouts for quick detection (<10s total)
            proxy_connect_timeout 1s;
            proxy_send_timeout 3s;
            proxy_read_timeout 3s;

            # Forward headers to client
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;

            # Pass app headers unchanged
            proxy_pass_header X-App-Pool;
            proxy_pass_header X-Release-Id;
        }
    }
}
EOF

# Validate config
nginx -t

# Start Nginx in foreground
exec nginx -g 'daemon off;'
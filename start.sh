#!/bin/sh
set -e

# Debug: Print environment variables
echo "ACTIVE_POOL is set to: $ACTIVE_POOL"

# Set defaults if ACTIVE_POOL is unset or invalid
if [ "$ACTIVE_POOL" = "blue" ]; then
  PRIMARY="app_blue:3000"
  BACKUP="app_green:3000"
  APP_POOL="blue"
elif [ "$ACTIVE_POOL" = "green" ]; then
  PRIMARY="app_green:3000"
  BACKUP="app_blue:3000"
  APP_POOL="green"
else
  echo "Warning: ACTIVE_POOL invalid or unset, defaulting to blue"
  PRIMARY="app_blue:3000"
  BACKUP="app_green:3000"
  APP_POOL="blue"
fi

# Debug: Print variables
echo "PRIMARY: $PRIMARY"
echo "BACKUP: $BACKUP"
echo "APP_POOL: $APP_POOL"

# Generate Nginx config
cat > /etc/nginx/nginx.conf << EOF
events {
    worker_connections 1024;
}
http {
    upstream primary {
        server ${PRIMARY} max_fails=1 fail_timeout=5s;
    }
    upstream backup {
        server ${BACKUP} max_fails=1 fail_timeout=5s backup;
    }
    server {
        listen 80;
        location / {
            proxy_pass http://primary;
            proxy_set_header X-App-Pool ${APP_POOL};
            proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
            proxy_next_upstream_tries 1;
            proxy_next_upstream_timeout 3s;
            proxy_connect_timeout 1s;
            proxy_send_timeout 3s;
            proxy_read_timeout 3s;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_pass_header X-App-Pool;
            proxy_pass_header X-Release-Id;
        }
    }
}
EOF

# Debug: Print generated config
cat /etc/nginx/nginx.conf

# Test config
nginx -t

# Start Nginx
exec nginx -g 'daemon off;'
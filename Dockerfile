FROM n8nio/n8n:latest

ENV NODE_ENV=production

USER root

# Install Postgres client and utilities
RUN apk update \
  && apk add --no-cache postgresql-client su-exec curl \
  && rm -rf /var/cache/apk/*

# Create custom nodes folder and install the package
RUN mkdir -p /home/node/.n8n/nodes \
  && cd /home/node/.n8n/nodes \
  && npm install -g --no-audit --omit=dev --unsafe-perm n8n-nodes-browserless

# Copy custom entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Secure and flexible permissions
RUN chmod -R 777 /home/node/.n8n /usr/local/lib/node_modules

WORKDIR /data

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]

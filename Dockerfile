# n8n Custom Image
#
# Extend official n8n image with custom nodes or dependencies.
# Build is handled automatically by install.sh.
#
# Manual build: docker build -t n8nio/n8n:custom .

ARG N8N_VERSION=latest
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install community nodes (uncomment as needed)
# RUN npm install -g n8n-nodes-browserless
# RUN npm install -g n8n-nodes-postgres

# Install system dependencies (if needed)
# RUN apk add --no-cache python3 py3-pip build-base

USER node

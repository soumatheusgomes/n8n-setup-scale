FROM n8nio/n8n:latest

USER root
RUN apk add --no-cache --virtual .build-deps python3 make g++ git \
 && npm install --no-audit --omit=dev --unsafe-perm n8n-nodes-browserless \
 && apk del .build-deps \
 && rm -rf /root/.npm /home/node/.cache

USER node
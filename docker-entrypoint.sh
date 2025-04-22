#!/bin/sh
set -e

app_data_dir="/home/node/.n8n"

if [ ! -d "$app_data_dir" ]; then
  mkdir -p "$app_data_dir"
fi

chown -R node:node "$app_data_dir"

if [ "$#" -gt 0 ]; then
  # Got started with arguments
  exec su-exec node "$@"
else
  # Got started without arguments
  exec su-exec node n8n
fi

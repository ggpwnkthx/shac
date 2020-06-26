#!/bin/sh
SERVICE_ID=$(echo $1 | jq -r '.Actor.ID')
curl --unix-socket /var/run/docker.sock http://x/services/$SERVICE_ID 2>/dev/null | jq

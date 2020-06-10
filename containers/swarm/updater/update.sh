#!/bin/sh

# Pull latest git
cd /usr/src/shac
git reset --hard HEAD
git clean -f -d
git pull
chmod +x start.sh
chmod +x update.sh

# Rebuild local container images
for img in $(ls -1 /usr/src/shac/containers/local); do
    if [ -d /usr/src/shac/containers/local/$img ]; then
        cd /usr/src/shac/containers/local/$img
        docker build . -t shac/$img
    fi
done
# Rebuild swarm container images
for img in $(ls -1 /usr/src/shac/containers/swarm); do
    if [ -d /usr/src/shac/containers/swarm/$img ]; then
        cd /usr/src/shac/containers/swarm/$img
        docker build . -t shac/$img
    fi
done
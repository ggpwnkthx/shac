#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )

get_running_updates() {
    docker service ls | \
    grep updater_updater | \
    awk '{print $4}' | \
    awk -F/ '{print $1}'
}

update_sequence() {
    docker stack rm seaweedfs
    env SRC=$BASEPATH docker stack deploy -c $BASEPATH/containers/swarm/updater/docker-compose.yml updater
    #while [ $(get_running_updates) -gt 0 ]; do sleep 1; done
    #docker stack rm updater
    #$BASEPATH/start.sh
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    update_sequence
fi
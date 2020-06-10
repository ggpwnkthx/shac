#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )

update_sequence() {
    docker stack rm seaweedfs
    env SRC=$BASEPATH docker stack deploy -c $BASEPATH/containers/swarm/updater/docker-compose.yml updater
    while [ "$(docker service ls | grep updater_updater | awk '{print $4}')" != "0/0" ]; do sleep 1; done
    docker stack rm updater
    $BASEPATH/start.sh
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    update_sequence
fi
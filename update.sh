#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )
DATA_DIR=${DATA_DIR:="/srv/cluster"}
if [ -f $DATA_DIR/config ]; then
    . $DATA_DIR/config
fi

update_stacks() {
    env SEAWEEDFS_DIR=$DATA_DIR/seaweedfs docker stack deploy -c $BASEPATH/containers/swarm/seaweedfs/docker-compose.yml seaweedfs
}

update_sequence() {
    env SRC=$BASEPATH docker stack deploy -c $BASEPATH/containers/swarm/updater/docker-compose.yml updater
    while [ "$(docker service ls | grep updater_updater | awk '{print $4}')" != "0/0" ]; do sleep 1; done
    docker stack rm updater
    update_stacks
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    update_sequence
fi
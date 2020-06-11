#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )
DATA_DIR=${DATA_DIR:="/srv/cluster"}
if [ -f $DATA_DIR/config ]; then
    . $DATA_DIR/config
fi

update_stacks() {
    # Update the SeaweedFS stack
    env SEAWEEDFS_DIR=$DATA_DIR/seaweedfs docker stack deploy -c $BASEPATH/docker/compose/seaweedfs.yml seaweedfs
}

update_sequence() {
    # Remove the old updater stack
    docker stack rm updater
    # Wait for the old updater stack to actuall be removed
    while [ ! -z "$(docker network ls | grep updater_default)" ]; do sleep 1; done
    # Deploy updater stack
    env SRC=$BASEPATH docker stack deploy -c $BASEPATH/docker/compose/updater.yml updater
    # Wait for all the services in the stack to complete and exit
    while [ "$(docker service ls | grep updater_updater | awk '{print $4}')" != "0/0" ]; do sleep 1; done
    # Update all the stacks
    update_stacks
    # Rerun startup script
    $BASEPATH/start.sh
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    update_sequence
fi
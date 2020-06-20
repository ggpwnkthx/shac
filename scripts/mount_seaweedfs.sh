#!/bin/sh

# Default variables
MOUNT_POINT=$1
WEED_BIN=$2

# Get the health status of a container by it's ID
get_container_status() {
    curl --unix-socket /var/run/docker.sock http://x/containers/$1/json 2>/dev/null | jq -r '.State.Health.Status'
}
get_local_container_ids() {
    NODE=$(curl --unix-socket /var/run/docker.sock http://x/nodes/$(hostname) 2>/dev/null | jq -r '.ID')
    curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
    jq --arg NODE $NODE --arg SERVICE $1 -r '.[] | select (.Labels."com.docker.swarm.node.id"==$NODE) | select (.Labels."com.docker.swarm.service.name"==$SERVICE) | .Id'
}
get_gwbridge_ip() {
    curl --unix-socket /var/run/docker.sock http://x/networks/docker_gwbridge 2>/dev/null | \
    jq --arg ID $1 -r '.Containers."\($ID)".IPv4Address' | \
    awk -F/ '{print $1}'
}
# Wait until all given container IDs are in a healthy state
wait_for_containers() {
    timeout=120
    interval=10
    for id in $@; do
        i=0
        echo "Waiting for $id..."
        while [ "healthy" != "$(get_container_status $id)" ]; do 
            i=$(($i + $interval))
            if [ $i -gt $timeout ]; then
                echo "$id was not found to be healthy in $timeout seconds."
                echo "If the distributed storage system is not healthy, the script cannot continue."
                exit 1
            fi
            sleep $interval
        done
    done
}
wait_for_mount() {
    timeout=60
    interval=10
    i=0
    while ! mountpoint -q -- "$1"; do
        i=$(($i + $interval))
        if [ $i -gt $timeout ]; then
            echo "Mount point not initialized for some reason."
            exit 1
        fi
        sleep $interval
    done
}
seaweedfs_mount() {
    while [ -z "$(lsmod | grep '^fuse ')" ]; do modprobe fuse; done
    while [ -z "$(get_local_container_ids seaweedfs_filer)" ]; do sleep 5; done;
    wait_for_containers $(get_local_container_ids seaweedfs_filer)
    ip=$(get_gwbridge_ip $(get_local_container_ids seaweedfs_filer))
    nohup $2 mount -dir=$1 -filer=$ip:80 -outsideContainerClusterMode &
    wait_for_mount $1
    if mountpoint -q -- "$1"; then
        if [ ! -f $1/fs/ready ]; then
            mkdir $1/fs
            touch $1/fs/ready
        fi
    fi
}

seaweedfs_mount $MOUNT_POINT $WEED_BIN
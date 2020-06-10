#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )
DATA_DIR=${DATA_DIR:="/srv/cluster"}
if [ -f $DATA_DIR/config ]; then
    . $DATA_DIR/config
fi
ORCH_VLAN_LINK=${ORCH_VLAN_LINK:="eth0"}
ORCH_VLAN_ID=${ORCH_VLAN_ID:=2}
ORCH_VLAN_NAME=${ORCH_VLAN_NAME:="orchestration"}
CIDR=${CIDR:="10.2.0.0/20"}
DOMAIN=${DOMAIN:="example.com"}

# Restart docker daemon in the most convenient way available
restart_docker() {
    if [ -f /etc/init.d/docker ]; then /etc/init.d/docker restart; return; fi
    if [ ! -z "$(which service)" ]; then service docker restart; return; fi
    if [ ! -z "$(which systemctl)" ]; then systemctl restart docker.service; return; fi
}

# Add or update config value
config_set() {
    grep -q '^$1' $DATA_DIR/config && sed -i "s/^$1.*/$1=$2/" $DATA_DIR/config || echo "$1=$2" >> $DATA_DIR/config
}

# Use the network-manager image to configure the host's network interfaces
startup_orchstration_vlan() {
    # Skip config if our expected IP address is already reachable
    if [ $(ping -c 1 $(echo $CIDR | awk -F/ '{print $1}') >/dev/null ; echo $?) -gt 0 ];  then 
        docker run --rm \
            --cap-add NET_ADMIN \
            --net=host \
            -v $DATA_DIR/config:/mnt/config \
            shac/network-manager \
            setup-orch-net $ORCH_VLAN_LINK $ORCH_VLAN_NAME $ORCH_VLAN_ID $CIDR
        restart_docker
    fi
}

startup_keepalived() {
    if ! -f $DATA_DIR/services/keepalived; then
        mkdir -p $DATA_DIR/services
        touch $DATA_DIR/services/keepalived
    fi
    docker run -d \
        --name keepalived \
        --net host \
        --cap-add NET_ADMIN \
        --restart always \
        -v $DATA_DIR/services/keepalived:/mnt/conf:share
        shac/keepalived \
            $ORCH_VLAN_NAME \
            $(date +%s | sha256sum | base64 | head -c 32 ; echo)
}

startup_networking() {
    startup_orchstration_vlan
}

# Get the health status of a container by it's ID
get_container_status() {
    curl --unix-socket /var/run/docker.sock http://x/containers/$1/json 2>/dev/null | jq -r '.State.Health.Status'
}

get_local_container_ids() {
    NODE=$(curl --unix-socket /var/run/docker.sock http://x/nodes/$(hostname) 2>/dev/null | jq -r '.ID')
    curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
    jq --arg NODE $NODE --arg SERVICE $1 -r '.[] | select (.Labels."com.docker.swarm.node.id"==$NODE) | select (.Labels."com.docker.swarm.service.name"==$SERVICE) | .Id'
}
# Wait until all given container IDs are in a healthy state
wait_for_containers() {
    timeout=120
    interval=10
    for id in $@; do
        i=0
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

startup_storage() {
    wait_for_containers $(get_local_container_ids seaweedfs_master) $(get_local_container_ids seaweedfs_volume) $(get_local_container_ids seaweedfs_filer)
}

bootstrap_local() {
    chmod +x $BASEPATH/update.sh
    mkdir -p $DATA_DIR
    touch $DATA_DIR/config
    # Skip bootstrap if it's already been done
    if [ -z "$BOOTSTRAP_LOCAL" ]; then 
        chmod +x $BASEPATH/scripts/bootstrap_local.sh
        $BASEPATH/scripts/bootstrap_local.sh \
            $BASEPATH \
            $CIDR \
            $DOMAIN
        config_set BOOTSTRAP_LOCAL 1
    fi
}
bootstrap_swarm() {
    if [ -z "$BOOTSTRAP_SWARM" ]; then 
        chmod +x $BASEPATH/scripts/bootstrap_swarm.sh
        $BASEPATH/scripts/bootstrap_swarm.sh \
            $BASEPATH \
            $DATA_DIR \
            $ORCH_VLAN_LINK \
            $ORCH_VLAN_ID \
            $ORCH_VLAN_NAME \
            $CIDR \
            $DOMAIN
        config_set BOOTSTRAP_SWARM 1
    fi
}

startup_sequence() {
    bootstrap_local
    startup_networking
    bootstrap_swarm
    startup_storage
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    startup_sequence
fi
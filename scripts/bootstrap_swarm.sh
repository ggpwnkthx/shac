#!/bin/sh

# Default variables
BASEPATH=$1
DATA_DIR=$2
if [ -f $DATA_DIR/config ]; then
    . $DATA_DIR/config
fi
ORCH_VLAN_LINK=${ORCH_VLAN_LINK:=$3}
ORCH_VLAN_ID=${ORCH_VLAN_ID:=$4}
ORCH_VLAN_NAME=${ORCH_VLAN_NAME:=$5}
CIDR=${CIDR:=$6}
DOMAIN=${DOMAIN:=$7}

# Dynamic Variables
DOCKER_LOCAL_BRIDGE_CIDR() {
    if [ -z "$DOCKER_LOCAL_BRIDGE_CIDR" ]; then
        DOCKER_LOCAL_BRIDGE_CIDR=$(shift_ip $(ipcalc $(echo $CIDR | awk -F/ '{print $1"/"$2+2}') | grep Broadcast | awk '{print $2}') 2)/$(echo $CIDR | awk -F/ '{print $2+2}')
    fi
    echo $DOCKER_LOCAL_BRIDGE_CIDR
}
DOCKER_SWARM_BRIDGE_CIDR() {
    if [ -z "$DOCKER_SWARM_BRIDGE_CIDR" ]; then
        DOCKER_SWARM_BRIDGE_CIDR=$(shift_ip $(ipcalc $(DOCKER_LOCAL_BRIDGE_CIDR) | grep Broadcast | awk '{print $2}') 2)/$(DOCKER_LOCAL_BRIDGE_CIDR | awk -F/ '{print $2-1}')
    fi
    echo $DOCKER_SWARM_BRIDGE_CIDR
}

# Use docker containers for tool abstraction
ipcalc() { 
    docker run -i --rm shac/network-manager ipcalc $@ 
}
shift_ip() { 
    docker run -i --rm shac/network-manager shift-ip $@ 
}
dig() {
    docker run -i --rm shac/network-manager dig $@ 
}

service_discovery() {
    if [ ! -z "$DNS_SERVER_IP" ]; then
        DOCKER_SWARM_MANAGER_TOKEN=$(dig _manager._swarm.$DOMAIN TXT @$DNS_SERVER_IP)
        DOCKER_SWARM_PORT=$(dig _swarm._tcp.$DOMAIN SRV @$DNS_SERVER_IP)
    fi
}

# Build all the container images located in the containers/swarm directory reletive to this script
build_container_images() {
    for img in $(ls -1 $BASEPATH/containers/swarm); do
        if [ -d $BASEPATH/containers/swarm/$img ]; then
            cd $BASEPATH/containers/swarm/$img
            docker build . -t shac/$img
        fi
    done
}

# Initialize the docker swarm
init_docker_swarm() {
    if [ -z "$(docker swarm join-token manager 2>/dev/null)" ]; then
        docker network create \
            --subnet=$(ipcalc $(DOCKER_SWARM_BRIDGE_CIDR) | grep Network | awk '{print $2}') \
            --gateway=$(DOCKER_SWARM_BRIDGE_CIDR | awk -F/ '{print $1}') \
            -o com.docker.network.bridge.enable_icc=false \
            -o com.docker.network.bridge.name=docker_gwbridge \
            -o com.docker.network.bridge.enable_ip_masquerade=true \
            docker_gwbridge
        docker swarm init \
            --listen-addr $(echo $CIDR | awk -F/ '{print $1}'):2377 \
            --advertise-addr $(echo $CIDR | awk -F/ '{print $1}'):2377 >/dev/null
    fi
}

bootstrap_distributed_storage() {
    mkdir -p $DATA_DIR/seaweedfs/config
    mkdir -p $DATA_DIR/seaweedfs/master
    mkdir -p $DATA_DIR/seaweedfs/volumes
    mkdir -p $DATA_DIR/seaweedfs/filer
    mkdir -p $DATA_DIR/seaweedfs/mount
    export SEAWEEDFS_DIR=$DATA_DIR/seaweedfs
    docker stack deploy -c $BASEPATH/containers/swarm/seaweedfs/docker-compose.yml $SEAWEEDFS_DIR
}

# Join an existing docker swarm
join_docker_swarm() {
    docker swarm join --token $DOCKER_SWARM_MANAGER_TOKEN $DNS_SERVER_IP:$DOCKER_SWARM_PORT
}

bootstrap() {
    # Use service discovery to bootstrap or join the cluster
    service_discovery
    if [ -z "$DOCKER_SWARM_MANAGER_JOIN" ]; then
        init_docker_swarm
        bootstrap_distributed_storage
    else
        join_docker_swarm
    fi
}

bootstrap
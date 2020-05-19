#!/bin/sh

# Default variables
BASEPATH=$1
DATA_DIR=$2
ORCH_VLAN_NAME=$3
CIDR=$4
DOMAIN=$5

# Dynamic Variables
DOCKER_LOCAL_BRIDGE_CIDR() {
    if [ -z "$DOCKER_LOCAL_BRIDGE_CIDR" ]; then
        DOCKER_LOCAL_BRIDGE_CIDR=$(shift-ip $(ipcalc $(echo $CIDR | awk -F/ '{print $1"/"$2+2}') | grep Broadcast | awk '{print $2}') 2)/$(echo $CIDR | awk -F/ '{print $2+2}')
    fi
    echo $DOCKER_LOCAL_BRIDGE_CIDR
}
DOCKER_SWARM_BRIDGE_CIDR() {
    if [ -z "$DOCKER_SWARM_BRIDGE_CIDR" ]; then
        DOCKER_SWARM_BRIDGE_CIDR=$(shift-ip $(ipcalc $(DOCKER_LOCAL_BRIDGE_CIDR) | grep Broadcast | awk '{print $2}') 2)/$(DOCKER_LOCAL_BRIDGE_CIDR | awk -F/ '{print $2-1}')
    fi
    echo $DOCKER_SWARM_BRIDGE_CIDR
}

# Use docker containers for tool abstraction
ipcalc() { 
    docker run -i --rm shac/network-manager ipcalc $@ 
}
shift-ip() { 
    docker run -i --rm shac/network-manager shift-ip $@ 
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
            --listen-addr $ORCH_VLAN_NAME:2377 \
            --advertise-addr $ORCH_VLAN_NAME:2377 >/dev/null
    fi
}

bootstrap() {
    # Use service discovery to bootstrap or join the cluster
    if [ ! -f $DATA_DIR/swarm/bootstrap_complete ]; then
        mkdir -p $DATA_DIR/swarm
        service_discovery
        if [ -z "$DOCKER_SWARM_MANAGER_IP" ]; then
            init_docker_swarm
        else
            join_docker_swarm
        fi
        touch $DATA_DIR/swarm/bootstrap_complete
    fi
}

bootstrap
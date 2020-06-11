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
jq() { 
    docker run -i --rm shac/base jq $@ 
}
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
    DATACENTER=${DATACENTER:="default_dc"}
    RACK=${RACK:="default_rk"}

    mkdir -p $DATA_DIR/seaweedfs/etcd
    mkdir -p $DATA_DIR/seaweedfs/filer
    mkdir -p $DATA_DIR/seaweedfs/master
    mkdir -p $DATA_DIR/seaweedfs/mount
    mkdir -p $DATA_DIR/seaweedfs/volumes

    if [ -f $BASEPATH/bin/weed ]; then mv $BASEPATH/bin/weed $DATA_DIR/seaweedfs/weed; fi

    docker_node=$(curl --unix-socket /var/run/docker.sock http://x/nodes/$(hostname) 2>/dev/null | jq -r '.ID')
    docker_node_datacenter=$(curl --unix-socket /var/run/docker.sock http://x/nodes/$docker_node 2>/dev/null | jq -r '.Spec.Labels.datacenter')
    docker_node_rack=$(curl --unix-socket /var/run/docker.sock http://x/nodes/$docker_node 2>/dev/null | jq -r '.Spec.Labels.rack')
    if [ "$docker_node_datacenter" = "null" ]; then
        docker node update --label-add datacenter=$DATACENTER $docker_node
    fi
    if [ "$docker_node_rack" = "null" ]; then
        docker node update --label-add rack=$RACK $docker_node
    fi
    
    services=$(curl --unix-socket /var/run/docker.sock http://x/services 2>/dev/null | jq -r '.[] | select(.Spec.Labels."com.docker.stack.namespace"=="seaweedfs") | .Spec.Name')
    if [ -z "$services" ]; then
        env SEAWEEDFS_DIR=$DATA_DIR/seaweedfs docker stack deploy -c $BASEPATH/docker/compose/seaweedfs.yml seaweedfs
    else
        env SEAWEEDFS_DIR=$DATA_DIR/seaweedfs docker stack deploy --prune -c $BASEPATH/docker/compose/seaweedfs.yml seaweedfs
        services=$(curl --unix-socket /var/run/docker.sock http://x/services 2>/dev/null | jq -r '.[] | select(.Spec.Labels."com.docker.stack.namespace"=="seaweedfs") | .Spec.Name')
        for s in $services; do
            docker service update --force --update-parallelism 1 $seaweedfs
        done
    fi
}

# Join an existing docker swarm
join_docker_swarm() {
    docker swarm join --token $DOCKER_SWARM_MANAGER_TOKEN $DNS_SERVER_IP:$DOCKER_SWARM_PORT
}

bootstrap() {
    # Use service discovery to bootstrap or join the cluster
    service_discovery
    swarm_id=$(curl --unix-socket /var/run/docker.sock http://x/swarm 2>/dev/null | jq -r '.ID')
    if [ "$swarm_id" = "null" ]; then
        if [ -z "$DOCKER_SWARM_MANAGER_JOIN" ]; then
            init_docker_swarm
        else
            join_docker_swarm
        fi
    fi
    bootstrap_distributed_storage
}

bootstrap
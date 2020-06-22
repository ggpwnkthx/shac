#!/bin/sh

# Default variables
CONFIG_FILE="/etc/shac.conf"
if [ -f $CONFIG_FILE ]; then
    . $CONFIG_FILE
fi
BASEPATH=$1
DATA_DIR=$2
SWARM_LINK_NAME=${SWARM_LINK_NAME:=$3}
CIDR=${CIDR:=$4}
DOMAIN=${DOMAIN:=$5}

# Dynamic Variables
DOCKER_SWARM_BRIDGE_CIDR() {
    if [ -z "$DOCKER_SWARM_BRIDGE_CIDR" ]; then
        broadcast=$(ipcalc $(echo $CIDR | awk -F/ '{print $1"/"$2+2}') | grep Broadcast | awk '{print $2}')
        DOCKER_LOCAL_BRIDGE_CIDR=$(shift_ip $broadcast 2)/$(echo $CIDR | awk -F/ '{print $2+2}')
        bbroadcast=$(ipcalc $DOCKER_LOCAL_BRIDGE_CIDR | grep Broadcast | awk '{print $2}')
        DOCKER_SWARM_BRIDGE_CIDR=$(shift_ip $bbroadcast 2)/$(echo $DOCKER_LOCAL_BRIDGE_CIDR | awk -F/ '{print $2-1}')
    fi
}

# Use docker containers for tool abstraction
ipcalc() { 
    docker run -i --rm shac/network-manager ipcalc $@ 
}
shift_ip() { 
    docker run -i --rm shac/network-manager shift-ip $@ 
}
digg() {
    docker run -i --rm shac/network-manager dig $@ | grep "^$1" | sed -n -e "s/.*$2//p" | xargs
}

service_discovery() {
    if [ ! -z "$DNS_SERVER_IP" ]; then
        DOCKER_SWARM_MANAGER_TOKEN=$(digg _manager._docker-swarm.$DOMAIN TXT @$DNS_SERVER_IP)
        DOCKER_SWARM_PORT=$(digg _docker-swarm._tcp.$DOMAIN SRV @$DNS_SERVER_IP)
        DATACENTER=$(digg _datacenter._local.$DOMAIN TXT @$DNS_SERVER_IP)
        RACK=$(digg _rack._local.$DOMAIN TXT @$DNS_SERVER_IP)
    fi
}

# Initialize the docker swarm
init_docker_swarm() {
    if [ -z "$(docker swarm join-token manager 2>/dev/null)" ]; then
        DOCKER_SWARM_BRIDGE_CIDR
        subnet=$(ipcalc $DOCKER_SWARM_BRIDGE_CIDR) | grep Network | awk '{print $2}')
        docker network create \
            --subnet=$subnet \
            --gateway=$DOCKER_SWARM_BRIDGE_CIDR | awk -F/ '{print $1}') \
            -o com.docker.network.bridge.enable_icc=false \
            -o com.docker.network.bridge.name=docker_gwbridge \
            -o com.docker.network.bridge.enable_ip_masquerade=true \
            docker_gwbridge
        docker swarm init \
            --listen-addr $SWARM_LINK_NAME:2377 \
            --advertise-addr $SWARM_LINK_NAME:2377 >/dev/null
    fi
}

bootstrap_seaweedfs() {
    if [ -f $BASEPATH/bin/weed ]; then 
        DATACENTER=${DATACENTER:="default_dc"}
        RACK=${RACK:="default_rk"}

        mkdir -p $DATA_DIR/seaweedfs/etcd
        mkdir -p $DATA_DIR/seaweedfs/filer
        mkdir -p $DATA_DIR/seaweedfs/master
        mkdir -p $DATA_DIR/seaweedfs/mount
        mkdir -p $DATA_DIR/seaweedfs/volumes
        
        mv $BASEPATH/bin/weed $DATA_DIR/seaweedfs/weed

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
            echo "Deploying seaweedfs stack..."
            env SEAWEEDFS_DIR=$DATA_DIR/seaweedfs docker stack deploy -c $BASEPATH/docker/compose/seaweedfs.yml seaweedfs
        else
            echo "Updating seaweedfs services..."
            docker service update --force seaweedfs_master
            docker service update --force seaweedfs_volume
            docker service update --force seaweedfs_filer
        fi
    fi
}

# Join an existing docker swarm
join_docker_swarm() {
    docker swarm join --token $DOCKER_SWARM_MANAGER_TOKEN $DNS_SERVER_IP:$DOCKER_SWARM_PORT
}

bootstrap() {
    # Use service discovery to bootstrap or join the cluster
    service_discovery
    swarm_id=$(curl --unix-socket /var/run/docker.sock http://x/info 2>/dev/null | jq -r '.Swarm.NodeID')
    if [ -z "$swarm_id" ]; then
        if [ -z "$DOCKER_SWARM_MANAGER_JOIN" ]; then
            init_docker_swarm
        else
            join_docker_swarm
        fi
    fi
    bootstrap_seaweedfs
}

bootstrap
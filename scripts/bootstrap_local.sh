#!/bin/sh

# Default variables
BASEPATH=$1
DATA_DIR=$2
ORCH_VLAN_LINK=$3
ORCH_VLAN_ID=$4
ORCH_VLAN_NAME=$5
CIDR=$6
DOMAIN=$7

# Dynamic Variables
DOCKER_LOCAL_BRIDGE_CIDR() {
    if [ -z "$DOCKER_LOCAL_BRIDGE_CIDR" ]; then
        DOCKER_LOCAL_BRIDGE_CIDR=$(shift-ip $(ipcalc $(echo $CIDR | awk -F/ '{print $1"/"$2+2}') | grep Broadcast | awk '{print $2}') 2)/$(echo $CIDR | awk -F/ '{print $2+2}')
    fi
    echo $DOCKER_LOCAL_BRIDGE_CIDR
}

# Use docker containers for tool abstraction
jq() { 
    docker run -i --rm shac/base jq $@ 
}
ipcalc() { 
    docker run -i --rm shac/network-manager ipcalc $@ 
}
shift-ip() { 
    docker run -i --rm shac/network-manager shift-ip $@ 
}
generate-name() { 
    docker run -i --rm shac/network-manager generate-name $@ 
}

# Enable the ip_vs kernel module
enable_ipvs() {
    if [ ! -f /etc/modules-load.d/ip_vs.conf ]; then
        echo ip_vs > /etc/modules-load.d/ip_vs.conf
    fi
    if [ -z "$(cat /proc/modules | grep '^ip_vs ')" ]; then
        modprobe ip_vs
    fi
}

update_hostname() {
    echo $1.$DOMAIN > /etc/hostname
    hostname $(cat /etc/hostname)
    sed -i "/^127.0.1.1/c\127.0.1.1 $(hostname)" /etc/hosts
}

# Restart docker daemon in the most convenient way available
restart_docker() {
    if [ -f /etc/init.d/docker ]; then /etc/init.d/docker restart; return; fi
    if [ ! -z "$(which service)" ]; then service docker restart; return; fi
    if [ ! -z "$(which systemctl)" ]; then systemctl restart docker.service; return; fi
}

# Adjust the docker bridge network used for local containers
fix_docker_bridge() {
    touch /etc/docker/daemon.json
    if [ -z "$(cat /etc/docker/daemon.json)" ]; then echo "{ }" > /etc/docker/daemon.json; fi
    cat /etc/docker/daemon.json | docker run -i --rm shac/base jq --arg ip $(DOCKER_LOCAL_BRIDGE_CIDR) '."bip"=$ip' > /etc/docker/daemon.json
    restart_docker
}

bootstrap_network() {
    if [ -z "$(cat /etc/hostname | grep $DOMAIN)" ]; then
        update_hostname $(generate-name).$DOMAIN
    fi
    enable_ipvs
    fix_docker_bridge
}

# Build all the container images located in the containers/local directory reletive to this script
build_container_images() {
    cd $BASEPATH/containers/base
    docker build . -t shac/base
    for img in $(ls -1 $BASEPATH/containers/local); do
        if [ -d $BASEPATH/containers/local/$img ]; then
            cd $BASEPATH/containers/local/$img
            docker build . -t shac/$img
        fi
    done
}

bootstrap() {
    # Get the local host configured
    if [ ! -f $DATA_DIR/local/bootstrap_complete ]; then
        mkdir -p $DATA_DIR/local
        build_container_images
        bootstrap_network
        touch $DATA_DIR/local/bootstrap_complete
    fi
}

bootstrap
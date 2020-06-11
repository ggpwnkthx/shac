#!/bin/sh

# Default variables
BASEPATH=$1
DATA_DIR=$2
CIDR=$3
DOMAIN=$4

# Dynamic Variables
DOCKER_LOCAL_BRIDGE_CIDR() {
    if [ -z "$DOCKER_LOCAL_BRIDGE_CIDR" ]; then
        local_cidr=$(echo $CIDR | awk -F/ '{print $1"/"$2+2}')
        local_brodcast=$(ipcalc $local_cidr | grep Broadcast | awk '{print $2}')
        docker_ip=$(shift_ip $local_brodcast 2)
        bitmask=$(echo $local_cidr | awk -F/ '{print $2}')
        DOCKER_LOCAL_BRIDGE_CIDR=$docker_ip/$bitmask
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
shift_ip() { 
    docker run -i --rm shac/network-manager shift-ip $@ 
}
generate_name() { 
    docker run -i --rm shac/network-manager generate-name $@ 
}
github_release_installer() {
    docker run -i --rm -v $BASEPATH:/usr/src/shac shac/base /usr/bin/github-release-installer $@
}

update_hostname() {
    echo $1 > /etc/hostname
    hostname $(cat /etc/hostname)
    sed -i "/^127.0.1.1/c\127.0.1.1 $(hostname -f) $(hostname -s)" /etc/hosts
}

# Adjust the docker bridge network used for local containers
fix_docker_bridge() {
    if [ -f /etc/docker/daemon.json ]; then
        if [ -z "$(cat /etc/docker/daemon.json)" ]; then 
            json="{ }"
        else
            json=$(cat /etc/docker/daemon.json)
        fi
    else
        json="{ }"
    fi
    DOCKER_LOCAL_BRIDGE_CIDR
    echo $json | jq --arg ip $DOCKER_LOCAL_BRIDGE_CIDR '.bip=$ip' > /etc/docker/daemon.json
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

bootstrap_network() {
    if [ -z "$(cat /etc/hostname | grep $DOMAIN)" ]; then
        update_hostname $(generate_name).$DOMAIN
    fi
    fix_docker_bridge
    enable_ipvs
}

download_binaries() {
    if [ ! -d $BASEPATH/bin ]; then
        mkdir -p $BASEPATH/bin
        github_release_installer chrislusf/seaweedfs /usr/src/shac/bin
    fi
    if [ -f $BASEPATH/bin/weed ]; then mv $BASEPATH/bin/weed $DATA_DIR/seaweedfs/weed; fi
}

# Build all the docker images
build_docker_images() {
    cd $BASEPATH/docker/build/base
    if [ -z "$(docker images | grep ^shac/base)" ]; then
        docker build . -t shac/base
    fi
    for img in $(ls -1 $BASEPATH/docker/build); do
        if [ "$img" != "base" ]; then
            if [ -d $BASEPATH/docker/build/$img ]; then
                cd $BASEPATH/docker/build/$img
                if [ -z "$(docker images | grep ^shac/$img)" ]; then
                    docker build . -t shac/$img
                fi
            fi
        fi
    done
}

bootstrap() {
    # Get the local host configured
    build_docker_images
    download_binaries
    bootstrap_network
}

bootstrap
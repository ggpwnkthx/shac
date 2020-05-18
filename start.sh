#!/bin/sh

# Default variables
DATA_DIR=${DATA_DIR:="/srv/cluster"}
ORCH_VLAN_LINK=${ORCH_VLAN_LINK:="eth0"}
ORCH_VLAN_ID=${ORCH_VLAN_ID:=2}
ORCH_VLAN_NAME=${ORCH_VLAN_NAME:="orchestration"}
CIDR=${CIDR:="10.2.0.0/20"}

# Dynamic Variables
BASEPATH=$( cd ${0%/*} && pwd -P )

update_hostname() {
    echo $1 > /etc/hostname
    hostname $(cat /etc/hostname)
    sed -i "/^127.0.1.1/c\127.0.1.1 $(hostname)" /etc/hosts
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

# Use the network-manager image to configure the host's network interfaces
network_config() {
    # Skip config if our expected IP address is already reachable
    if [ -f $DATA_DIR/local ]; then
        if [ $(ping -c 1 $(cat $DATA_DIR/local/ip | awk -F/ '{print $1}') >/dev/null ; echo $?) -eq 0 ];  then return; fi
    fi
    docker run --rm \
        --cap-add NET_ADMIN \
        --net=host \
        -v $DATA_DIR/local:/mnt/local \
        shac/network-manager \
        setup-orch-net $ORCH_VLAN_LINK $ORCH_VLAN_NAME $ORCH_VLAN_ID $CIDR
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
    docker_bridge_ip=$(docker run --rm --net=host shac/network-manager ipcalc $(cat /srv/cluster/local/ip) | grep Broadcast | awk '{print $2}')
    docker_bridge_ip=$(docker run --rm --net=host shac/network-manager shift-ip $docker_bridge_ip 2)/$(cat /srv/cluster/local/ip | awk -F/ '{print $2}')
    cat /etc/docker/daemon.json | docker run -i --rm shac/base jq --arg ip $docker_bridge_ip '."bip"=$ip' > /etc/docker/daemon.json
    restart_docker
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

bootstrap() {
    mkdir -p $DATA_DIR/local
    build_container_images
    if [ -z "$(cat /etc/hostname | awk -F- '{print $2}')" ]; then
        update_hostname $(docker run --rm shac/network-manager generate-name)
    fi
    network_config
    fix_docker_bridge
    enable_ipvs
    touch $DATA_DIR/local/bootstrap_complete
}

start_up_sequence() {
    # Skip bootstrap if it's already been done
    if [ ! -f $DATA_DIR/local/bootstrap_complete ]; then 
        bootstrap
    fi
    network_config
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    start_up_sequence
fi
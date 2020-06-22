#!/bin/sh

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
        ;;
        -C|--cidr)
            CIDR="$2"
            shift 2
        ;;
        -d|--data)
            DATA_DIR="$2"
            shift 2
        ;;
        -D|--domain)
            DOMAIN="$2"
            shift 2
        ;;
        --orch-link)
            ORCH_NET_LINK="$2"
            shift 2
        ;;
        --orch-name)
            ORCH_LINK_NAME="$2"
            shift 2
        ;;
        --orch-vlan)
            ORCH_VLAN_ID="$2"
            shift 2
        ;;
        --datacenter)
            DATACENTER="$2"
            shift 2
        ;;
        --rack)
            RACK="$2"
            shift 2
        ;;
    esac
done

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )
CONFIG_FILE=${CONFIG_FILE:="/etc/shac.conf"}
DATA_DIR=${DATA_DIR:="/srv/cluster"}
CIDR=${CIDR:="10.2.0.0/20"}
ORCH_NET_LINK=${ORCH_NET_LINK:="$(ip link | grep -v '^.*: lo' | grep -v '^ ' | head -n 1 | awk -F: '{print $2}' | xargs)"}
ORCH_LINK_NAME=${ORCH_LINK_NAME:="orchestration"}
ORCH_VLAN_ID=${ORCH_VLAN_ID:="2"}
DOMAIN=${DOMAIN:="develop.shac"}
DATACENTER=${DATACENTER="default_dc"}
RACK=${RACK="default_rk"}
if [ -f $CONFIG_FILE ]; then
    . $CONFIG_FILE
fi

# Unset ORCH_VLAN_ID if it's not a number - assume it means untagged.
if [ -z "$(echo $ORCH_VLAN_ID | grep '^[0-9]*$')" ]; then unset ORCH_VLAN_ID; fi

# Test output variables
echo "#----------------------------------#"
echo "CONFIG_FILE=$CONFIG_FILE"
echo "DATA_DIR=$DATA_DIR"
echo "CIDR=$CIDR"
echo "ORCH_NET_LINK=$ORCH_NET_LINK"
echo "ORCH_LINK_NAME=$ORCH_LINK_NAME"
echo "ORCH_VLAN_ID=$ORCH_VLAN_ID"
echo "DOMAIN=$DOMAIN"
echo "DATACENTER=$DATACENTER"
echo "RACK=$RACK"
echo "#----------------------------------#"

# Restart docker daemon in the most convenient way available
wait_for_docker() {
    unset docker_ready
    while [ -z "$docker_ready" ]; do docker_ready=$(docker ps 2>/dev/null | head -n 1 | grep 'CONTAINER ID'); done
}
start_docker() {
    if [ -f /etc/init.d/docker ]; then /etc/init.d/docker start; return; fi
    if [ ! -z "$(which systemctl)" ]; then systemctl start docker.service; return; fi
    if [ ! -z "$(which service)" ]; then service docker start; return; fi
    wait_for_docker
}
restart_docker() {
    if [ -f /etc/init.d/docker ]; then /etc/init.d/docker restart; return; fi
    if [ ! -z "$(which systemctl)" ]; then systemctl restart docker.service; return; fi
    if [ ! -z "$(which service)" ]; then service docker restart; return; fi
    wait_for_docker
}

# Use docker containers for tool abstraction
ipcalc() { 
    docker run -i --rm shac/network-manager ipcalc $@ 
}

# Add or update config value
config_set() {
    grep '^$1' $CONFIG_FILE && sed -i "s/^$1.*/$1=$2/" $CONFIG_FILE || echo "$1=$2" >> $CONFIG_FILE
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
}
check_prerequisites() {
    if ! command_exists docker; then
        echo "Docker doesn't seem to be installed. Cannot continue without it."
        exit 1
    fi
    start_docker
}

# Use the network-manager image to configure the host's network interfaces
startup_orchstration_net() {
    echo "Initializing orchestration network..."
    orch_cidr=$(echo $CIDR | awk -F/ '{print $1}')/$(($(echo $CIDR | awk -F/ '{print $2}') + 2))
    docker run --rm \
        --cap-add NET_ADMIN \
        --net=host \
        -v $CONFIG_FILE:/mnt/config \
        shac/network-manager \
        setup-net \
            $orch_cidr \
            $ORCH_NET_LINK \
            $ORCH_LINK_NAME \
            $ORCH_VLAN_ID
    restart_docker
    echo "... orchstration network initialized."
}

startup_networking() {
    if [ -z "$ORCH_CIDR" ]; then
        startup_orchstration_net
    else
        # Skip config if our expected IP address is already reachable
        if [ $(ping -c 1 $(echo $ORCH_CIDR | awk -F/ '{print $1}') >/dev/null ; echo $?) -gt 0 ];  then
            startup_orchstration_net
        fi
    fi
}

mount_distributed_storage() {
    if mountpoint -q -- "$DATA_DIR/seaweedfs/mount"; then
        umount $DATA_DIR/seaweedfs/mount
    fi
    while ! mountpoint -q -- "$DATA_DIR/seaweedfs/mount"; do
        $BASEPATH/scripts/mount_seaweedfs.sh $DATA_DIR/seaweedfs/mount $DATA_DIR/seaweedfs/weed
    done
}

bootstrap_dnsmasq() {
    if [ ! -f $DATA_DIR/seaweedfs/mount/services/dnsmasq/leases ]; then
        mkdir -p $DATA_DIR/seaweedfs/mount/services/dnsmasq
        touch $DATA_DIR/seaweedfs/mount/services/dnsmasq/leases
    fi
}

bootstrap_configs() {
    bootstrap_dnsmasq
}

bootstrap_local() {
    wait_for_docker
    chmod +x $BASEPATH/update.sh
    chmod +x $BASEPATH/scripts/*
    mkdir -p $DATA_DIR
    touch $CONFIG_FILE
    chmod +x $BASEPATH/scripts/bootstrap_local.sh
    $BASEPATH/scripts/bootstrap_local.sh \
        $BASEPATH \
        $DATA_DIR \
        $CIDR \
        $DOMAIN
}
bootstrap_swarm() {
    wait_for_docker
    $BASEPATH/scripts/bootstrap_swarm.sh \
        $BASEPATH \
        $DATA_DIR \
        $ORCH_LINK_NAME \
        $CIDR \
        $DOMAIN
}

startup_dnsmasq() {
    ORCH_CIDR=$(ip a show $ORCH_LINK_NAME | grep 'inet ' | awk '{print $2}')
    ip_min=$(ipcalc $ORCH_CIDR | grep HostMin | awk '{print $2}')
    ip_max=$(ipcalc $ORCH_CIDR | grep HostMax | awk '{print $2}')
    netmask=$(ipcalc $ORCH_CIDR | grep Netmask | awk '{print $2}')
    join_token=$(docker swarm join-token manager | grep docker | awk '{print $5}')
    join_ip=$(docker swarm join-token manager | grep docker | awk '{print $6}' | awk -F: '{print $1}')
    join_port=$(docker swarm join-token manager | grep docker | awk '{print $6}' | awk -F: '{print $2}')
    docker run -d \
        --net=host \
        --cap-add=NET_ADMIN \
        -v $DATA_DIR/seaweedfs/mount/services/dnsmasq:/mnt \
        shac/network-manager \
            dnsmasq -d \
                --bogus-priv \
                --no-resolv \
                --no-poll \
                --no-hosts \
                --interface=$ORCH_LINK_NAME \
                --bind-interfaces \
                --domain=$DOMAIN \
                --dhcp-leasefile=/mnt/leases \
                --dhcp-range=$ip_min,$ip_max,$netmask,infinite \
                --txt-record=_manager._docker-swarm.$DOMAIN,$join_token \
                --srv-host=_docker-swarm._tcp.$DOMAIN,$join_ip,$join_port \
                --txt-record=_datacenter._local.$DOMAIN,$DATACENTER \
                --txt-record=_rack._local.$DOMAIN,$RACK
}

startup_services() {
    startup_dnsmasq
}

clean_up() {
    # Remove exited containers
    exited_containers=$(docker ps -a -q -f status=exited)
    if [ ! -z "$exited_containers" ]; then
        docker rm -v $exited_containers
    fi
    # Clean up old, untagged, docker images
    old_containers=$(docker images | grep '^<none>' | awk '{print $3}')
    if [ ! -z "$old_containers" ]; then
        docker rmi $old_containers
    fi
    
    config_set BASEPATH $BASEPATH
    config_set DATA_DIR $DATA_DIR
    config_set ORCH_NET_LINK $ORCH_NET_LINK
    config_set ORCH_VLAN_ID $ORCH_VLAN_ID
    config_set ORCH_LINK_NAME $ORCH_LINK_NAME
    config_set CIDR $CIDR
    config_set DOMAIN $DOMAIN
}

startup_sequence() {
    check_prerequisites
    bootstrap_local
    startup_networking
    bootstrap_swarm
    mount_distributed_storage
    bootstrap_configs
    startup_services
    clean_up
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    startup_sequence
fi
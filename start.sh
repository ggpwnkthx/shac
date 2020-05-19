#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )
DATA_DIR=${DATA_DIR:="/srv/cluster"}
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

# Use the network-manager image to configure the host's network interfaces
startup_orchstration_vlan() {
    # Skip config if our expected IP address is already reachable
    if [ -f $DATA_DIR/local/ip ]; then
        if [ $(ping -c 1 $(cat $DATA_DIR/local/ip | awk -F/ '{print $1}') >/dev/null ; echo $?) -gt 0 ];  then 
            docker run --rm \
                --cap-add NET_ADMIN \
                --net=host \
                -v $DATA_DIR/local:/mnt/local \
                shac/network-manager \
                setup-orch-net $ORCH_VLAN_LINK $ORCH_VLAN_NAME $ORCH_VLAN_ID $CIDR
        fi
    fi
}

startup_networking() {
    startup_orchstration_vlan
    restart_docker
}

startup_storage() {
    echo "do storage things..."
}

bootstrap_local() {
    # Skip bootstrap if it's already been done
    if [ ! -f $DATA_DIR/local/bootstrap_complete ]; then 
        chmod +x $BASEPATH/scripts/bootstrap_local.sh
        $BASEPATH/scripts/bootstrap_local.sh \
            $BASEPATH \
            $DATA_DIR \
            $ORCH_VLAN_LINK \
            $ORCH_VLAN_ID \
            $ORCH_VLAN_NAME \
            $CIDR \
            $DOMAIN
    fi
}
bootstrap_swarm() {
    if [ ! -f $DATA_DIR/swarm/bootstrap_complete ]; then 
        chmod +x $BASEPATH/scripts/bootstrap_swarm.sh
        $BASEPATH/scripts/bootstrap_swarm.sh \
            $BASEPATH \
            $DATA_DIR \
            $ORCH_VLAN_NAME \
            $CIDR \
            $DOMAIN
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
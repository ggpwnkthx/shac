#!/bin/sh

# Default variables
data_dir=${data_dir:="/srv/cluster"}
orch_vlan_link=${orch_vlan_link:="eth0"}
orch_vlan_id=${orch_vlan_id:=2}
orch_vlan_name=${orch_vlan_name:="orchestration"}
cidr=${cidr:="10.2.0.0/20"}

# Dynamic Variables
BASEPATH=$( cd ${0%/*} && pwd -P )

# Build all the container images located in the containers/local directory reletive to this script
build_container_images() {
    cd $BASEPATH/containers/base
    docker build --no-cache . -t shac-base
    if [ -d $BASEPATH/containers/local/$img ]; then
        if [ "$(docker image inspect local/$img 2>/dev/null)" = "[]" ]; then 
            cd $BASEPATH/containers/local/$img
            docker build --no-cache . -t shac-$img
        fi
    fi
}

# Restart docker daemon in the most convenient way available
restart_docker() {
    if [ -f /etc/init.d/docker ]; then /etc/init.d/docker restart; return; fi
    if [ ! -z "$(which service)" ]; then service docker restart; return; fi
    if [ ! -z "$(which systemctl)" ]; then systemctl restart docker.service; return; fi
}

# Use the network-manager image to configure the host's network interfaces
network_config() {
    docker run --rm \
        --cap-add NET_ADMIN \
        --net=host \
        -v /srv/cluster/local:/mnt/local \
        local/network-manager \
        setup-orch-net $orch_vlan_link $orch_vlan_name $orch_vlan_id $cidr
}

fix_docker_bridge() {
    cat /etc/docker/daemon.json | sudo toolkit jq '."bip"="test"' > /etc/docker/daemon.json
    restart_docker
}

bootstrap() {
    mkdir -p $data_dir/local
    build_container_images
    network_config
}

wrapper() {
    bootstrap
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    wrapper
fi
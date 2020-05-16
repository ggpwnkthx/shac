#!/bin/sh

# Default variables
orch_vlan_link=${orch_vlan_link:="eth0"}
orch_vlan_id=${orch_vlan_id:=2}
orch_vlan_name=${orch_vlan_name:="orchestration"}
cidr=${cidr:="10.2.0.0/20"}
cluster_user=${cluster_user:="cluster-manager"}
cluster_password=${cluster_password:="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"}
data_dir=${data_dir:="/srv/cluster"}
seaweedfs=${seaweedfs:="$data_dir/seaweedfs/mount"}
datacenter=${datacenter:="1"}
rack=${rack:="1"}

# Dynamic Variables
BASEPATH=$( cd ${0%/*} && pwd -P )

build_container_images() {
    if [ "$(docker image inspect local/base 2>/dev/null)" = "[]" ]; then 
        cd $BASEPATH/containers/base
        docker build . -t local/base
    fi
    for img in $(ls -1 $BASEPATH/containers/local); do
        if [ -d $BASEPATH/containers/local/$img ]; then
            if [ "$(docker image inspect local/$img 2>/dev/null)" = "[]" ]; then 
                cd $BASEPATH/containers/local/$img
                docker build . -t local/$img
            fi
        fi
    done
}

link_toolkit() {
    chmod +x $BASEPATH/scripts/toolkit.sh
    ln -s $BASEPATH/scripts/toolkit.sh /usr/bin/toolkit
}

bootstrap() {
    build_container_images
    link_toolkit
}

sudo bootstrap
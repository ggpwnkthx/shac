#!/bin/sh
SERVICE=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.swarm.service.name"' | \
    awk -F_ '{print $NF}'
)
NODE=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.swarm.node.id"'
)
if [ -z "$DATACENTER" ]; then
    DATACENTER=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE 2>/dev/null | \
        jq -r '.Spec.Labels.datacenter'
    )
    if [ "$DATACENTER" == "null" ]; then unset DATACENTER; fi
fi

if [ -z "$RACK" ]; then
    RACK=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE 2>/dev/null | \
        jq -r '.Spec.Labels.rack' \
    )
    if [ "$RACK" == "null" ]; then unset RACK; fi
fi
get_masters() {
    echo $( \
        for c in $(curl --unix-socket /var/run/docker.sock http://x/tasks 2>/dev/null | jq -r '.[] | select(.Spec.Networks[].Aliases | index ("master")) | select(.Status.State=="running") | .Status.ContainerStatus.ContainerID'); do
            echo "$(curl --unix-socket /var/run/docker.sock http://x/containers/$c/json 2>/dev/null | jq -r '.NetworkSettings.Networks.seaweedfs_default.IPAddress'):80"
        done;
    ) | \
    sed -e 's/\s\+/,/g'
}
get_local_filer() {
    for ip in $( \
        curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
        jq -r "
            .[] | 
            select (.Labels.\"com.docker.swarm.node.id\"==\"$NODE\") | 
            select (.Labels.\"com.docker.swarm.service.name\"==\"seaweedfs_filer\") | 
            .NetworkSettings.Networks.seaweedfs_default.IPAMConfig.IPv4Address
        "
    ); do echo "$ip:80"; done
}
get_ip() {
    cat /etc/hosts | grep $(hostname) | awk '{print $1}'
}

wait_for_master() {
    while [ $(get_masters | wc -w) -eq 0 ]; do sleep 5; done
}
wait_for_filer() {
    while [ $(get_local_filer | wc -w)  -eq 0 ]; do sleep 5; done
}


case "$SERVICE" in
    'master')
        ARGS="$ARGS -port=80 -mdir=/data -volumePreallocate"
        if [ ! -z "$MAX_VOLUME_SIZE" ]; then ARGS="$ARGS -volumeSizeLimitMB=$MAX_VOLUME_SIZE"; fi
        if [ ! -z "$REPLICATION" ]; then ARGS="$ARGS -defaultReplication=$REPLICATION"; fi
        if [ $(get_masters | wc -w) -gt 0 ]; then 
            ARGS="$ARGS -peers=$(get_masters)"
        fi
    ;;
    'volume')
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        if [ ! -z "$RACK" ]; then ARGS="$ARGS -rack=$RACK"; fi
        if [ ! -z "$MAX_VOLUMES" ]; then ARGS="$ARGS -max=$MAX_VOLUMES"; fi
        wait_for_master
        ARGS="$ARGS -port=80 -dir=/data -mserver=$(get_masters)"
        ;;
    'filer')
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        wait_for_master
        ARGS="$ARGS -port=80 -master=$(get_masters)"
        ;;
    'mount')
        wait_for_filer
        ARGS="$ARGS -dir=/mnt -filer=$(get_local_filer)"
        ;;
    's3')
        if [ ! -f /run/secret/seaweedfs_key ]; then echo "Certificate key secret 'seaweedfs_key' not provided."; exit 1; fi
        if [ ! -f /run/secret/seaweedfs_cert ]; then echo "Certificate secret 'seaweedfs_cert' not provided."; exit 1; fi
        if [ ! -z "$DOMAIN_NAME" ]; then ARGS="$ARGS --domainName=$DOMAIN_NAME"; fi
        wait_for_filer
        ARGS="$ARGS -port=80 -filer=$(get_local_filer) -key.file=/run/secret/key -cert.file=/run/secret/cert"
        ;;
    'webdav')
        wait_for_filer
        ARGS="$ARGS -port=80 -filer=$(get_local_filer)"
        ;;
esac
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

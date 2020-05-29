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
fi
if [ -z "$RACK" ]; then
    RACK=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE 2>/dev/null | \
        jq -r '.Spec.Labels.rack' \
    )
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
case "$SERVICE" in
    'master')
        ARGS="$ARGS -port=80 -mdir=/data -volumePreallocate"
        if [ ! -z "$MAX_VOLUME_SIZE" ]; then ARGS="$ARGS -volumeSizeLimitMB=$MAX_VOLUME_SIZE"; fi
        if [ ! -z "$REPLICATION" ]; then ARGS="$ARGS -defaultReplication=$REPLICATION"; fi
        if [ $(get_masters | wc -m) -gt 1 ]; then 
            ARGS="$ARGS -peers=$(get_masters)"
        fi
    ;;
    'volume')
        ARGS="$ARGS -port=80"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        if [ ! -z "$RACK" ]; then ARGS="$ARGS -rack=$RACK"; fi
        if [ ! -z "$MAX_VOLUMES" ]; then ARGS="$ARGS -max=$MAX_VOLUMES"; fi
        while [ $(get_masters | wc -m) -lt 1 ]; do sleep 1; done
        ARGS="$ARGS -dir=/data -mserver=$(get_masters)"
        ;;
    'filer')
        ARGS="$ARGS -port=80"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        while [ $(get_masters | wc -m) -lt 1 ]; do sleep 1; done
        ARGS="$ARGS -master=$(get_masters)"
        ;;
    'mount')
        ARGS="$ARGS -dir=/mnt"
        while [ $(get_local_filer | wc -w) -lt 1 ]; do sleep 1; done
        ARGS="$ARGS -filer=$(get_local_filer)"
        ;;
    's3')
        ARGS="$ARGS -port=80"
        if [ ! -f /run/secret/seaweedfs_key ]; then echo "Certificate key secret 'seaweedfs_key' not provided."; exit 1; fi
        if [ ! -f /run/secret/seaweedfs_cert ]; then echo "Certificate secret 'seaweedfs_cert' not provided."; exit 1; fi
        ARGS="$ARGS -key.file=/run/secret/key -cert.file=/run/secret/cert"
        if [ ! -z "$DOMAIN_NAME" ]; then ARGS="$ARGS --domainName=$DOMAIN_NAME"; fi
        while [ $(get_local_filer | wc -w) -lt 1 ]; do sleep 1; done
        ARGS="$ARGS -filer=$(get_local_filer)"
        ;;
    'webdav')
        ARGS="$ARGS -port=80"
        while [ $(get_local_filer | wc -w) -lt 1 ]; do sleep 1; done
        ARGS="$ARGS -filer=$(get_local_filer)"
        ;;
esac
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

#!/bin/sh

# Discover service mode by environmental variable or through swarm label
if [ -z "$SERVICE" ]; then
    SERVICE=$( \
        curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
        jq -r '.Config.Labels."com.docker.swarm.service.name"' | \
        awk -F_ '{print $NF}'
    )
fi

# Discover container ID
ID=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Id'
)

# Get local docker node hostname by environmental variable or through swarm label
if [ -z "$NODE" ]; then
    # Discover the local node ID and the task ID
    NODE_ID=$( \
        curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
        jq -r '.Config.Labels."com.docker.swarm.node.id"'
    )
    NODE=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE_ID | \
        jq -r '.Description.Hostname' | \
        awk -F. '{print $1}'
    )
fi

# Discover datacenter and rack details via environmental variables or through node labels.
# If nothing found, unset the variables so seaweedfs uses internal defaults.
if [ -z "$DATACENTER" ]; then
    DATACENTER=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE 2>/dev/null | \
        jq -r '.Spec.Labels.datacenter'
    )
    if [ "$DATACENTER" = "null" ]; then unset DATACENTER; fi
fi
if [ -z "$RACK" ]; then
    RACK=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE 2>/dev/null | \
        jq -r '.Spec.Labels.rack' \
    )
    if [ "$RACK" = "null" ]; then unset RACK; fi
fi

# Discover all the container IDs for a given service name
get_all_service_ids() {
    ips=$( \
        curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
        jq -r '.[] | select(.State!="exited") | select(.Labels."com.docker.swarm.service.name" | index ("$1")) | .Id'
    )
    for id in $ids; do
        if [ "$id" != "$ID" ]; then echo $id; fi
    done
}
# Get the health status of a container by it's ID
get_container_status() {
    curl --unix-socket /var/run/docker.sock http://x/containers/$1/json 2>/dev/null | jq -r '.State.Health.Status'
}
# Wait until all given container IDs are in a healthy state
wait_for_containers() {
    for id in $@; do
        while [ "healthy" != "$(get_container_status $id)" ]; do sleep 1; done
    done
}

get_masters() {
    for id in $(get_all_service_ids seaweedfs_master); do
        curl --unix-socket /var/run/docker.sock http://x/containers/$id/json 2>/dev/null | \
        jq -r '.NetworkSettings.Networks.seaweedfs_default.IPAddress +":80"'
    done | \
    xargs | \
    sed -e 's/\s\+/,/g'
}

case "$SERVICE" in
    'master')
        ARGS="$ARGS -port=80 -mdir=/data -volumePreallocate"
        if [ ! -z "$MAX_VOLUME_SIZE" ]; then ARGS="$ARGS -volumeSizeLimitMB=$MAX_VOLUME_SIZE"; fi
        if [ ! -z "$REPLICATION" ]; then ARGS="$ARGS -defaultReplication=$REPLICATION"; fi
        if [ $(get_masters | wc -w) -gt 0 ]; then 
            wait_for_containers $(get_all_service_ids seaweedfs_master)
            ARGS="$ARGS -peers=$(get_masters)"
        fi
    ;;
    'volume')
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        if [ ! -z "$RACK" ]; then ARGS="$ARGS -rack=$RACK"; fi
        if [ ! -z "$MAX_VOLUMES" ]; then ARGS="$ARGS -max=$MAX_VOLUMES"; fi
        wait_for_containers $(get_all_service_ids seaweedfs_master)
        ARGS="$ARGS -port=80 -dir=/data -mserver=$(get_masters)"
    ;;
    'filer')
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        wait_for_containers $(get_all_service_ids seaweedfs_master)
        ARGS="$ARGS -port=80 -master=$(get_masters)"
    ;;
    'mount')
        wait_for_containers $(get_all_service_ids seaweedfs_master)
        ARGS="$ARGS -dir=/data -filer="$NODE"_filer:80"
    ;;
    's3')
        if [ ! -f /run/secret/seaweedfs_key ]; then echo "Certificate key secret 'seaweedfs_key' not provided."; exit 1; fi
        if [ ! -f /run/secret/seaweedfs_cert ]; then echo "Certificate secret 'seaweedfs_cert' not provided."; exit 1; fi
        if [ ! -z "$DOMAIN_NAME" ]; then ARGS="$ARGS --domainName=$DOMAIN_NAME"; fi
        wait_for_containers "$NODE"_filer
        ARGS="$ARGS -port=80 -filer="$NODE"_filer:80 -key.file=/run/secret/key -cert.file=/run/secret/cert"
    ;;
    'webdav')
        wait_for_containers "$NODE"_filer
        ARGS="$ARGS -port=80 -filer="$NODE"_filer:80"
    ;;
esac
hostname
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

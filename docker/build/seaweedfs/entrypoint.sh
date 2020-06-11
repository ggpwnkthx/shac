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
# Discover the local node ID
NODE_ID=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.swarm.node.id"'
)

# Get local docker node hostname by environmental variable or through swarm label
if [ -z "$NODE" ]; then
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
    ids=$( \
        curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
        jq -r --arg SERVICE $1 '.[] | select(.State!="exited") | select(.Labels."com.docker.swarm.service.name"==$SERVICE) | .Id'
    )
    for id in $ids; do
        if [ "$id" != "$ID" ]; then echo $id; fi
    done
}
get_local_service_ids() {
    curl --unix-socket /var/run/docker.sock http://x/containers/json 2>/dev/null | \
    jq -r --arg NODE_ID $NODE_ID --arg SERVICE $1 '.[] | select(.State!="exited") | select(.Labels."com.docker.swarm.node.id"==$NODE_ID) | select(.Labels."com.docker.swarm.service.name"==$SERVICE) | .Id'
}
# Get the health status of a container by it's ID
get_container_status() {
    curl --unix-socket /var/run/docker.sock http://x/containers/$1/json 2>/dev/null | jq -r '.State.Health.Status'
}
# Wait until all given container IDs are in a healthy state
wait_for_containers() {
    for id in $@; do
        echo "Waiting for $id..." 
        while [ "healthy" != "$(get_container_status $id)" ]; do sleep 1; done
    done
}

get_container_ip() {
    curl --unix-socket /var/run/docker.sock http://x/networks/seaweedfs_default 2>/dev/null | \
    jq --arg ID $1 -r '.Containers."\($ID)".IPv4Address' | \
    awk -F/ '{print $1}'
}

# Wait for the filer's store to be healthy
wait_for_store() {
    store=$(head -n 1 /etc/seaweedfs/filer.toml | sed 's/[][]//g')
    echo "Waiting for $store..." 
    case $store in
        memory | leveldb | leveldb2)
            echo "No waiting needed."
        ;;
        mongodb)
            echo "TODO..."
        ;;
        casandra)
            echo "TODO..."
        ;;
        mysql)
            echo "TODO..."
        ;;
        postgres)
            echo "TODO..."
        ;;
        memsql)
            echo "TODO..."
        ;;
        tidb)
            echo "TODO..."
        ;;
        cockroachdb)
            echo "TODO..."
        ;;
        etcd)
            url="http://"$(echo $(cat /etc/seaweedfs/filer.toml | grep '^servers' | awk -F= '{print $2}' | sed 's/"//g'))"/health"
            echo "Waiting for $url..."
            while [ "$(curl $url 2>dev/null | jq -r '.health')" != "true" ]; do sleep 1; done
        ;;
        tikv)
            echo "TODO..."
        ;;
    esac
}

get_masters() {
    for id in $(get_all_service_ids seaweedfs_master); do
        echo "$(get_container_ip $id):80"
    done | \
    xargs | \
    sed -e 's/\s\+/,/g'
}

case "$SERVICE" in
    'master')
        ARGS="$ARGS -ip=$(get_container_ip $ID) -port=80 -mdir=/data -volumePreallocate"
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
        ARGS="$ARGS -ip=$(get_container_ip $ID) -port=80 -dir=/data -mserver=$(get_masters)"
    ;;
    'filer')
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        wait_for_containers $(get_all_service_ids seaweedfs_master)
        wait_for_store
        ARGS="$ARGS -ip=$(get_container_ip $ID) -port=80 -master=$(get_masters)"
    ;;
    'mount')
        wait_for_containers $(get_local_service_ids seaweedfs_filer)
        ARGS="$ARGS -dir=/data -filer=$(get_container_ip $(get_local_service_ids seaweedfs_filer)):80"
    ;;
    's3')
        if [ -f /run/secret/seaweedfs_key ]; then ARGS="$ARGS -key.file=/run/secret/seaweedfs_key"; fi
        if [ -f /run/secret/seaweedfs_cert ]; then ARGS="$ARGS -cert.file=/run/secret/seaweedfs_cert"; fi
        if [ ! -z "$DOMAIN_NAME" ]; then ARGS="$ARGS --domainName=$DOMAIN_NAME"; fi
        wait_for_containers $(get_local_service_ids seaweedfs_filer)
        ARGS="$ARGS -port=80 --filer=$(get_container_ip $(get_local_service_ids seaweedfs_filer)):80"
    ;;
    'webdav')
        wait_for_containers $(get_local_service_ids seaweedfs_filer)
        ARGS="$ARGS -port=80 -filer=$(get_container_ip $(get_local_service_ids seaweedfs_filer)):80"
    ;;
esac
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

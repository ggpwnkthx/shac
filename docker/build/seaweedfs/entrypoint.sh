#!/bin/bash

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
    jq -r '.Id' \
)
# Discover IP address
IP=$(
    curl --unix-socket /var/run/docker.sock http://x/networks/seaweedfs_default 2>/dev/null | \
    jq --arg ID $ID -r '.Containers."\($ID)".IPv4Address' | \
    awk -F/ '{print $1}'
)
# Discover the local node ID
NODE_ID=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.swarm.node.id"' \
)
# Discover Task ID
TASK_ID=$( \
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.swarm.task.id"' \
)

# Discover datacenter and rack details via environmental variables or through node labels.
# If nothing found, unset the variables so seaweedfs uses internal defaults.
if [ -z "$DATACENTER" ]; then
    DATACENTER=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE_ID 2>/dev/null | \
        jq -r '.Spec.Labels.datacenter'
    )
    if [ "$DATACENTER" = "null" ]; then unset DATACENTER; fi
fi
if [ -z "$RACK" ]; then
    RACK=$( \
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE_ID 2>/dev/null | \
        jq -r '.Spec.Labels.rack' \
    )
    if [ "$RACK" = "null" ]; then unset RACK; fi
fi

# Wait for the filer's store to be healthy
waitForFilerStore() {
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

waitForHTTP() {
    echo "Waiting for $1 ..."
    while [ -z "$html" ]; do
        html=$(curl -f $1 2>/dev/null)
    done
}
waitForHTTPByConnectionString() {
    IFS=',' read -r -a nodes <<< "$1"
    for node in ${nodes[@]}; do
        waitForHTTP http://$node$2
    done
}

# Configure arguments
case "$SERVICE" in
    'master')
        ARGS="$ARGS -ip=$IP -port=80 -mdir=/data -volumePreallocate"
        if [ ! -z "$MAX_VOLUME_SIZE" ]; then ARGS="$ARGS -volumeSizeLimitMB=$MAX_VOLUME_SIZE"; fi
        if [ ! -z "$REPLICATION" ]; then ARGS="$ARGS -defaultReplication=$REPLICATION"; fi
        ARGS="$ARGS -peers=master-1:80,master-2:80,master-3:80"
    ;;
    'volume')
        ARGS="$ARGS -ip=$IP -port=80 -dir=/data"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        if [ ! -z "$RACK" ]; then ARGS="$ARGS -rack=$RACK"; fi
        if [ ! -z "$MAX_VOLUMES" ]; then ARGS="$ARGS -max=$MAX_VOLUMES"; fi
        ARGS="$ARGS -mserver=master-1:80,master-2:80,master-3:80"
        waitForHTTPByConnectionString master-1:80,master-2:80,master-3:80
    ;;
    'filer')
        ARGS="$ARGS -ip=$IP -port=80"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        ARGS="$ARGS -master=master-1:80,master-2:80,master-3:80"
        waitForHTTPByConnectionString master-1:80,master-2:80,master-3:80
        waitForFilerStore
    ;;
    's3')
        if [ -f /run/secret/seaweedfs_key ]; then ARGS="$ARGS -key.file=/run/secret/seaweedfs_key"; fi
        if [ -f /run/secret/seaweedfs_cert ]; then ARGS="$ARGS -cert.file=/run/secret/seaweedfs_cert"; fi
        if [ ! -z "$DOMAIN_NAME" ]; then ARGS="$ARGS --domainName=$DOMAIN_NAME"; fi
        ARGS="$ARGS -port=80 --filer=filer:80"
        waitForHTTPByConnectionString filer:80
    ;;
    'webdav')
        ARGS="$ARGS -port=80 -filer=filer:80"
        waitForHTTPByConnectionString filer:80
    ;;
esac
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

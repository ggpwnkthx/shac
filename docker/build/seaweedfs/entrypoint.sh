#!/bin/bash

NAMESPACE=$(
    curl --unix-socket /var/run/docker.sock http://x/tasks/$TASK_ID 2>/dev/null | \
    jq -r '.Spec.ContainerSpec.Labels."com.docker.stack.namespace"'
)
TASK_SLOT=$(
    curl --unix-socket /var/run/docker.sock http://x/tasks/$TASK_ID 2>/dev/null | \
    jq -r '.Slot'
)
SERVICE=$(
    curl --unix-socket /var/run/docker.sock http://x/services/$SERVICE_ID 2>/dev/null | \
    jq -r '.Spec.Name' | \
    sed -n -e "s/^$NAMESPACE[_]//p"
)
HOST=$($NAMESPACE"_"$SERVICE)
if [ "$TASK_SLOT" != "null" ]; then HOST=$HOST"_"$TASK_SLOT; fi

# Discover datacenter and rack details via environmental variables or through node labels.
# If nothing found, unset the variables so seaweedfs uses internal defaults.
if [ -z "$DATACENTER" ]; then
    DATACENTER=$(
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE_ID 2>/dev/null | \
        jq -r '.Spec.Labels.datacenter'
    )
    if [ "$DATACENTER" = "null" ]; then unset DATACENTER; fi
fi
if [ -z "$RACK" ]; then
    RACK=$(
        curl --unix-socket /var/run/docker.sock http://x/nodes/$NODE_ID 2>/dev/null | \
        jq -r '.Spec.Labels.rack'
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

generateMasterConnectionString() {
    for slot in {1..3}; do
        if [ "$SERVICE" = "master" ]; then
            if [ $slot -ne $TASK_SLOT ]; then
                echo seaweedfs_master_$slot:80
            fi
        else
            echo seaweedfs_master_$slot:80
        fi
    done | \
    xargs | \
    sed -e 's/\s\+/,/g'
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
        ARGS="$ARGS -ip=$HOST -port=80 -mdir=/data -volumePreallocate"
        if [ ! -z "$MAX_VOLUME_SIZE" ]; then ARGS="$ARGS -volumeSizeLimitMB=$MAX_VOLUME_SIZE"; fi
        if [ ! -z "$REPLICATION" ]; then ARGS="$ARGS -defaultReplication=$REPLICATION"; fi
        ARGS="$ARGS -peers=$(generateMasterConnectionString)"
    ;;
    'volume')
        ARGS="$ARGS -ip=$HOST -port=80 -dir=/data"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        if [ ! -z "$RACK" ]; then ARGS="$ARGS -rack=$RACK"; fi
        if [ ! -z "$MAX_VOLUMES" ]; then ARGS="$ARGS -max=$MAX_VOLUMES"; fi
        ARGS="$ARGS -mserver=$(generateMasterConnectionString)"
        waitForHTTPByConnectionString $(generateMasterConnectionString)
    ;;
    'filer')
        ARGS="$ARGS -ip=$HOST -port=80"
        if [ ! -z "$DATACENTER" ]; then ARGS="$ARGS -dataCenter=$DATACENTER"; fi
        ARGS="$ARGS -master=$(generateMasterConnectionString)"
        waitForHTTPByConnectionString $(generateMasterConnectionString)
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

nohup swarm-hosts-updater $NAMESPACE &
echo "Running: /usr/bin/weed $SERVICE $ARGS"
/usr/bin/weed $SERVICE $ARGS

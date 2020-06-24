#!/bin/bash

NAMESPACE=$(
    curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
    jq -r '.Config.Labels."com.docker.stack.namespace"'
)

getTaskIDsByNamespace() {
    for ns in $@; do
        curl --unix-socket /var/run/docker.sock http://x/tasks 2>/dev/null | \
        jq -r --arg NAMESPACE $ns '
            .[] | 
            select(.Spec.ContainerSpec.Labels."com.docker.stack.namespace"==$NAMESPACE) | 
            select(.DesiredState=="running") |
            .ID
        '
    done
}
updateHostsFileRecordsByTaskID() {
    for tid in $@; do
        ns=$(
            curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
            jq -r '
                .Spec.ContainerSpec.Labels."com.docker.stack.namespace"
            '
        )
        ip=$(
            curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
            jq -r --arg NAMESPACE $ns '
                .NetworksAttachments[] |
                select(.Network.Spec.Name==$NAMESPACE+"_default") |
                .Addresses[]
            ' | \
            awk -F/ '{print $1}'
        )
        sid=$(
            curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
            jq -r '
                .ServiceID
            '
        )
        service=$(
            curl --unix-socket /var/run/docker.sock http://x/services/$sid 2>/dev/null | \
            jq -r '
                .Spec.Name
            '
        )
        slot=$(
            curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
            jq -r '
                .Slot
            '
        )
        if [ "$slot" != "null" ]; then
            hostname=$service"_"$slot; 
        else
            hostname=$service
        fi
        echo "[$(date)]: Updating $hostname record..."
        sed -i "/$hostname$/d" /hosts
        echo -e "$ip\t$hostname" >> /hosts
    done
}
while true; do
    echo "[$(date)]: Updating hosts..."
    updateHostsFileRecordsByTaskID $(getTaskIDsByNamespace $NAMESPACE)
    sleep 15
done
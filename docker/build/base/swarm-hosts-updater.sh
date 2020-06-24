#!/bin/bash

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
        record=$ip
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
            hostname=$record"_"$service"_"$slot; 
        else
            hostname=$record"_"$service
        fi
        sed -i "/$hostname$/d" /etc/hosts
        echo -e "$record\t$hostname" >> /etc/hosts
    done
}
while true; do
    updateHostsFileRecordsByTaskID $(getTaskIDsByNamespace $@)
    sleep 15
done
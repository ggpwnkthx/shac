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
generateHostRecordsByTaskID() {
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
        record="$record $service"
        slot=$(
            curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
            jq -r '
                .Slot
            '
        )
        if [ "$slot" != "null" ]; then record=$record"_"$slot; fi
        echo $record
    done
}
updateHostsFile() {
    sed -i "/$2$/d" /etc/hosts
    echo -e "$1\t$2" >> /etc/hosts
}
while true; do
    for tid in $(getTaskIDsByNamespace $@); do 
        updateHostsFile $(generateHostRecordsByTaskID $tid)
    done
    sleep 5
done
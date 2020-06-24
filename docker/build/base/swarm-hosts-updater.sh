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
        echo -e "$ip\t$hostname"
    done
}
while true; do
    echo "[$(date)]: Updating hosts"
    records=$(updateHostsFileRecordsByTaskID $(getTaskIDsByNamespace $NAMESPACE))
    cat > /hosts <<EOF
127.0.0.1       localhost
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
$records
EOF
    sleep 15
done
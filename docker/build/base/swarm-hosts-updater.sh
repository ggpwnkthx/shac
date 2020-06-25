#!/bin/bash

NAMESPACE=$@
if [ -z "$1" ]; then
    NAMESPACE=$(
        curl --unix-socket /var/run/docker.sock http://x/containers/$(hostname)/json 2>/dev/null | \
        jq -r '.Config.Labels."com.docker.stack.namespace"'
    )
fi

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
            node_id=$(
                curl --unix-socket /var/run/docker.sock http://x/tasks/$tid 2>/dev/null | \
                jq -r '
                    .NodeID
                '
            )
            hostname=$service.$node_id
        fi
        echo -e "$ip\t$hostname"
    done
}
while true; do
    echo "[$(date)]: Updating hosts"
    original=$(sed '/^# Dynamic Records/q' /etc/hosts | grep -v '# Dynamic Records')
    records=$(updateHostsFileRecordsByTaskID $(getTaskIDsByNamespace $NAMESPACE))
    cat > /etc/hosts <<EOF
$original
# Dynamic Records
$records
EOF
    sleep 15
done
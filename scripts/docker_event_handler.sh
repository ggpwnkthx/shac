#!/bin/sh

SCRIPTS_PATH=$1

monitor() {
    docker events --format '{{json .}}' | \
    while read event; do
        handle=$(echo $event | jq -r '.scope+","+.Type+","+.Action')
        scope=$(echo $handle | awk -F, '{print $1}')
        type=$(echo $handle | awk -F, '{print $2}')
        action=$(echo $handle | awk -F, '{print $3}' | awk -F: '{print $1}')
        echo $SCRIPTS_PATH/$scope/$type/$action >> $SCRIPTS_PATH/log
        if [ -d $SCRIPTS_PATH/$scope/$type/$action ]; then
            for script in $SCRIPTS_PATH/$scope/$type/$action/*; do
                nohup sh -c $script -s $event &
            done
        fi
    done
    monitor
}
check_lock() {
    exec 200>$SCRIPTS_PATH/lock
    flock -n 200 || exit 1
    pid=$$
    echo $pid 1>&200
}

# Exit if no handler script path provided
if [ -z "$SCRIPTS_PATH" ]; then 
    echo "No scripts path provided."
    exit 1; 
fi

# Exit if another handler is running
check_lock

# Start
monitor
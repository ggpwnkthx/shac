#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )

install() {
    case "$(cat /proc/1/comm)" in
        systemd)
            sed -i "s/^ExecStart.*/ExecStart=$BASEPATH/start.sh" $BASEPATH/services/systemd
            sed -i "s/^ExecReload.*/ExecReload=$BASEPATH/start.sh" $BASEPATH/services/systemd
            ln -s $BASEPATH/services/systemd /etc/systemd/system/simple-highly-available-cluster.service
            systemctl daemon-reload
            systemctl enable simple-highly-available-cluster.service
        ;;
    esac
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    install
fi
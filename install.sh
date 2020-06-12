#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )

install() {
    case "$(cat /proc/1/comm)" in
        systemd)
            sed -i "s/^ExecStart.*/ExecStart=$(echo $BASEPATH | sed 's/\//\\\//g')\/start.sh/" $BASEPATH/services/systemd
            if [ ! -f /etc/systemd/system/shac ]; then
                ln -s $BASEPATH/services/systemd /etc/systemd/system/shac.service
            fi
            systemctl daemon-reload
            systemctl enable shac.service
            systemctl start shac.service
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
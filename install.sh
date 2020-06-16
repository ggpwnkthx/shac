#!/bin/sh

# Default variables
BASEPATH=$( cd ${0%/*} && pwd -P )

install() {
    chmod +x $BASEPATH/start.sh
    case "$(cat /proc/1/comm | awk -F/ '{print $NF}')" in
        init)
            if [ -f /etc/init.d/shac ]; then rm /etc/init.d/shac; fi

            proxy_init=$(readlink $(which init) | awk -F/ '{print $NF}')
            case $proxy_init in
                busybox)
                    real_init=$( \
                        cat /etc/inittab | \
                        grep ':sysinit:' | \
                        head -n 1 | \
                        awk -F/ '{print $NF}' | \
                        awk '{print $1}'
                    )
                ;;
            esac

            case $real_init in
                openrc)
                    sed "s/^command.*/command=$(echo $BASEPATH | sed 's/\//\\\//g')\/start.sh/" $BASEPATH/services/openrc > /etc/init.d/shac
                    rc-update add shac default
                ;;
            esac
        ;;
        systemd)
            if [ -f /etc/systemd/system/shac.service ]; then rm /etc/systemd/system/shac.service; fi
            sed "s/^ExecStart.*/ExecStart=$(echo $BASEPATH | sed 's/\//\\\//g')\/start.sh/" $BASEPATH/services/systemd > /etc/systemd/system/shac.service
            systemctl daemon-reload
            systemctl enable shac.service
        ;;
    esac
    $BASEPATH/start.sh
}

# Rerun self if not root
user="$(id -un 2>/dev/null || true)"
if [ "$user" != 'root' ]; then
    sudo $0 $@
else
    install
fi
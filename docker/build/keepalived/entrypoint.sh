#!/bin/sh
if ! -f /mnt/conf; then
cat << EOF > /mnt/conf
vrrp_instance VI_1 {
    state MASTER
    interface $1
    virtual_router_id 51
    priority 255
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass $3
    }
    virtual_ipaddress {
        $2
    }
}
EOF
fi

keepalived -n -l -D -f /mnt/conf
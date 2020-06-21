#!/bin/bash
CIDR=$1
NET_LINK=$2
LINK_NAME=$3
VLAN_ID=$4

CONFIG_PATH=/mnt/config

if [ 24 -lt $(echo $CIDR | awk -F/ '{print $2}') ]; then
    echo ""
    echo "The provided bit mask of /$(echo $CIDR | awk -F/ '{print $2}') is too low for practical use."
    echo "The CIDR provided will be divided into multiple subnets and VLANs."
    echo "Any bit mask greater than 24 is not recommended, is unsupported, and will be rejected."
    echo "A CIDR similar to 10.2.0.0/20 is recommended."
    echo ""
    exit 1
fi

get_lease_option() {
    echo $(cat /var/lib/dhcp/dhclient.leases | grep "^option $1" | awk '{print $3}' | sed 's/.$//')
}

# Add or update config value
config_set() {
    grep '^$1' $CONFIG_PATH && sed -i 's/^$1.*/$1=$2/' $CONFIG_PATH || echo "$1=$2" >> $CONFIG_PATH
}
config_get() {
    cat $CONFIG_PATH | grep "^$1=" | awk -F= '{print $2}'
}

# Add the vlan interface if it doesn't exist
if [ -z "$(ip link show $LINK_NAME 2>/dev/null)" ]; then
    if [ ! -z "$VLAN_ID" ]; then
        ip link add link $NET_LINK name $LINK_NAME type vlan id $VLAN_ID
    else
        ip link set $NET_LINK down
        ip link set $NET_LINK name $LINK_NAME
        ip link set $LINK_NAME up
    fi
fi

# Check for pre-existing configuration
IP=$(config_get "$LINK_NAME"_CIDR)
if [ -z "$IP" ]; then
    # If no IP is detected, use dhclient to get one
    IP=$(ip -j address | jq -r --arg i "$LINK_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
    if [ -z "$IP" ]; then
        echo "timeout 10;" > /etc/dhcp/dhclient.conf
        dhclient -n -1 $LINK_NAME
    fi

    # If we didn't talk to a DHCP server, then we assumer we're the first on the network
    IP=$(ip -j address | jq -r --arg i "$LINK_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
    if [ -z "$IP" ]; then
        ip_min=$(ipcalc $CIDR | grep HostMin | awk '{print $2}')
        ip_max=$(ipcalc $CIDR | grep HostMax | awk '{print $2}')
        octet_1=$(shuf -i $(echo $ip_min | awk -F. '{print $1}')-$(echo $ip_max | awk -F. '{print $1}') -n 1)
        octet_2=$(shuf -i $(echo $ip_min | awk -F. '{print $2}')-$(echo $ip_max | awk -F. '{print $2}') -n 1)
        octet_3=$(shuf -i $(echo $ip_min | awk -F. '{print $3}')-$(echo $ip_max | awk -F. '{print $3}') -n 1)
        octet_4=$(shuf -i $(echo $ip_min | awk -F. '{print $4}')-$(echo $ip_max | awk -F. '{print $4}') -n 1)
        IP=$octet_1.$octet_2.$octet_3.$octet_4/$(echo $CIDR | awk -F/ '{print $2}')
    else
        config_set DNS_SERVER_IP $(get_lease_option dhcp-server-identifier)
        config_set DOMAIN $(get_lease_option domain-name)
    fi
    # Save our IP address
    config_set "$LINK_NAME"_CIDR $IP
fi
ip addr add $IP dev $LINK_NAME
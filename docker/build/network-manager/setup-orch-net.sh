#!/bin/sh
VLAN_LINK=$1
VLAN_NAME=$2
VLAN_ID=$3
CIDR=$4

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
BITMASK=$(($(echo $CIDR | awk -F/ '{print $2}') + 2))

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
if [ -z "$(ip link show $VLAN_NAME 2>/dev/null)" ]; then
    ip link add link $VLAN_LINK name $VLAN_NAME type vlan id $VLAN_ID
fi

# Check for pre-existing configuration
IP=$(config_get ORCH_VLAN_CIDR)
if [ -z "$IP" ]; then
    # If no IP is detected, use dhclient to get one
    IP=$(ip -j address | jq -r --arg i "$VLAN_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
    if [ -z "$IP" ]; then
        echo "timeout 10;" > /etc/dhcp/dhclient.conf
        dhclient -1 $VLAN_NAME
    fi

    # If we didn't talk to a DHCP server, then we assumer we're the first on the network
    IP=$(ip -j address | jq -r --arg i "$VLAN_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
    if [ -z "$IP" ]; then
        IP=$(shift-ip $(ipcalc $CIDR | grep HostMin | awk '{print $2}') +1)/$BITMASK
    else
        config_set DNS_SERVER_IP $(get_lease_option dhcp-server-identifier)
        config_set DOMAIN $(get_lease_option domain-name)
    fi
    # Save our IP address
    config_set ORCH_VLAN_CIDR $IP
fi
ip addr add $IP dev $VLAN_NAME
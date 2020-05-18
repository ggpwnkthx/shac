#!/bin/sh
VLAN_LINK=$1
VLAN_NAME=$2
VLAN_ID=$3
CIDR=$4

if [ 24 -lt $(echo $CIDR | awk -F/ '{print $2}') ]; then
    echo ""
    echo "The provided bit mask of /$(echo $CIDR | awk -F/ '{print $2}') is too low for practical use."
    echo "The CIDR provided will be divided into multiple subnets and VLANs."
    echo "Any bit mask greater than 24 is not recommended, is unsupported, and will be rejected."
    echo "A CIDR similar to 10.2.0.0/20 is recommended."
    echo ""
    exit 1
fi
BITMASK=$(($(echo $cidr | awk -F/ '{print $2}') + 2))

# Add the vlan interface if it doesn't exist
if [ -z "$(ip link show $VLAN_NAME)" ]; then
    ip link add link $VLAN_LINK name $VLAN_NAME type vlan id $VLAN_ID
fi

# If no IP is detected, use dhclient to get one
IP1=$(ip -j address | jq -r --arg i "$VLAN_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
if [ -z "$IP1" ]; then
    echo "timeout 10;" > /etc/dhcp/dhclient.conf
    dhclient -1 $VLAN_NAME
fi

# If we didn't talk to a DHCP server, then we assumer we're the first on the network
IP2=$(ip -j address | jq -r --arg i "$VLAN_NAME" '.[] | select(.ifname == $i) | .addr_info[] | select(.family == "inet") | .local')
if [ -z "$IP2" ]; then
    if [ -f /mnt/local/ip ]; then
        IP3=$(cat /mnt/local/ip)
    else
        IP3=$(shift-ip $(ipcalc $CIDR | grep HostMin | awk '{print $2}') +1)/$BITMASK
        # Save our IP address
        echo $IP3 > /mnt/local/ip
    fi
    ip addr add $IP3 dev $VLAN_NAME
fi
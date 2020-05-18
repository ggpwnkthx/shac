#!/bin/sh

# Usage dialog
usage() {
    cat >&2 <<-'EOF'
Usage:
shift_ip [ip address] [shift amount]

Examples:
shift_ip 192.168.45.16 +10
shift_ip 192.168.45.16 -64
EOF
exit 1
}

# Validate arguments
if [ -z "$2" ]; then usage; fi
if [ -z "$(echo $1 | awk -F. '{print $4}')"]; then usage; fi
for num in $(echo $1 | awk -F. '{print $1" "$2" "$3" "$4}'); do
    if $num -gt 255; then usage; fi
done

# Process
IPNUM=""
for i in $(echo $1 | awk -F. '{print $1" "$2" "$3" "$4}'); do
    IPNUM="$IPNUM""$(printf "%08d\n" $(echo "obase=2;$i" | bc))"
done
IPNUM=$(echo "ibase=2;obase=A;$IPNUM" | bc)

IPNUM=$(($IPNUM + $2))

IPNUM=$(echo "obase=2;$IPNUM" | bc)
if [ $(echo -n $IPNUM | wc -m) -gt 32 ]; then
    IPNUM=$(echo $IPNUM | grep -o "^.\{$(($(echo -n $IPNUM | wc -m) - 32))\}")
fi
if [ $(echo -n $IPNUM | wc -m) -lt 32 ]; then
    for i in $(seq 1 $((32 - $(echo -n $IPNUM | wc -m)))); do
        IPNUM=0$IPNUM
    done
fi
return=""
for i in $(echo $IPNUM | sed 's/.\{8\}/& /g'); do
    return=$return" "$(echo "ibase=2;obase=A;$i" | bc)
done
echo $return | awk '{print $1"."$2"."$3"."$4}'

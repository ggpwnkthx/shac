FROM shac/base

RUN apk --no-cache add ipcalc iproute2 dhclient bind-tools dnsmasq

ADD generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
ADD shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
ADD setup-orch-net.sh /usr/bin/setup-net
RUN chmod +x /usr/bin/setup-net
FROM shac/base

RUN apk --no-cache add iproute2 dhclient dnsmasq

ADD setup-net.sh /usr/bin/setup-net
RUN chmod +x /usr/bin/setup-net
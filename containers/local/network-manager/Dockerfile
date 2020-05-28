FROM shac/base

RUN apk add ipcalc
RUN apk add iproute2
RUN apk add dhclient
RUN apk add dig

ADD generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
ADD shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
ADD setup-orch-net.sh /usr/bin/setup-orch-net
RUN chmod +x /usr/bin/setup-orch-net
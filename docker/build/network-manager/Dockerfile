FROM shac/base

RUN apk --no-cache add ipcalc iproute2 dhclient bind-tools

ADD generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
ADD shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
ADD setup-orch-net.sh /usr/bin/setup-orch-net
RUN chmod +x /usr/bin/setup-orch-net
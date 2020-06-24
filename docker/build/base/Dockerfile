FROM alpine:3.12

RUN echo "@edge_main http://nl.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "@edge_testing http://nl.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    echo "@edge_community http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk --no-cache add bash bind-tools curl git ipcalc jq

COPY github-release-installer.sh /usr/bin/github-release-installer
RUN chmod +x /usr/bin/github-release-installer
COPY swarm-hosts-updater.sh /usr/bin/swarm-hosts-updater
RUN chmod +x /usr/bin/swarm-hosts-updater
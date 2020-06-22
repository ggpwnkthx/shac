FROM alpine:3.12

RUN echo "@edge http://nl.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "@testing http://nl.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    echo "@community http://nl.alpinelinux.org/alpine/v3.10/community" >> /etc/apk/repositories && \
    echo "@edgecommunity http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk --no-cache add bash curl jq ipcalc bind-tools

COPY generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
COPY shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
COPY github-release-installer.sh /usr/bin/github-release-installer
RUN chmod +x /usr/bin/github-release-installer
FROM shac/base

RUN apk --no-cache add fuse
RUN /usr/bin/github-release-installer chrislusf/seaweedfs /usr/bin

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
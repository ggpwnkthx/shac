FROM shac/base

RUN apk add fuse

COPY installer.sh /installer.sh
RUN chmod +x /installer.sh
RUN /installer.sh

RUN mkdir -p /etc/seaweedfs
COPY filer.toml /etc/seaweedfs/filer.toml

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
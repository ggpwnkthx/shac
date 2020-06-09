FROM shac/base

RUN apk add fuse

COPY installer.sh /installer.sh
RUN chmod +x /installer.sh
RUN /installer.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
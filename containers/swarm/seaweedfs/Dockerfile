FROM shac/base
RUN apk add wget
RUN apk add tar
RUN apk add davfs2
COPY installer.sh /installer.sh
RUN /installer.sh
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
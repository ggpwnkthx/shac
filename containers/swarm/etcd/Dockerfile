FROM shac/base

RUN apk --no-cache add bash bind-tools tini@community

COPY installer.sh /installer.sh
RUN chmod +x /installer.sh
RUN /installer.sh

COPY run.sh /bin/
RUN chmod +x /bin/run.sh
ENTRYPOINT ["/sbin/tini", "--", "/bin/run.sh"]
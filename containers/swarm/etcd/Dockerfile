FROM shac/base

RUN apk --no-cache add bash bind-tools tini@community
RUN /usr/bin/github-release-installer etcd-io/etcd /bin

COPY run.sh /bin/
RUN chmod +x /bin/run.sh
ENTRYPOINT ["/sbin/tini", "--", "/bin/run.sh"]
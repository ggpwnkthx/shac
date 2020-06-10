FROM shac/base

RUN apk --no-cache add bash bind-tools tini@community
RUN /usr/bin/github-release-installer etcd-io/etcd /tmp
RUN mv /tmp/etcd-*/etcd /etcd-*/etcdctl /bin/
RUN rm -rf /tmp/etcd-*

COPY run.sh /bin/
RUN chmod +x /bin/run.sh
ENTRYPOINT ["/sbin/tini", "--", "/bin/run.sh"]
FROM golang:alpine AS builder
RUN apk add git
RUN apk add g++
RUN mkdir -p /go/src/github.com/chrislusf/
RUN git clone https://github.com/chrislusf/seaweedfs /go/src/github.com/chrislusf/seaweedfs
RUN cd /go/src/github.com/chrislusf/seaweedfs/weed && go install

FROM shac/base AS final
COPY --from=builder /go/bin/weed /usr/bin/
RUN mkdir -p /etc/seaweedfs
COPY --from=builder /go/src/github.com/chrislusf/seaweedfs/docker/filer.toml /etc/seaweedfs/filer.toml

RUN mkdir -p /data/filerldb2
VOLUME /data

RUN apk add davfs2
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
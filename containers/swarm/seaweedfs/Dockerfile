FROM golang:alpine AS builder
RUN apk add git
RUN apk add g++
RUN mkdir -p /go/src/github.com/chrislusf/
RUN git clone https://github.com/chrislusf/seaweedfs /go/src/github.com/chrislusf/seaweedfs
RUN cd /go/src/github.com/chrislusf/seaweedfs/weed && go install

FROM shac/base AS final
COPY --from=builder /go/bin/weed /usr/bin/
RUN mkdir -p /etc/seaweedfs
COPY filer.toml /etc/seaweedfs/filer.toml

# volume server grpc port
EXPOSE 18080
# filer server grpc port
EXPOSE 18888
# master server shared grpc port
EXPOSE 19333
# http port
EXPOSE 80

RUN apk add davfs2
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
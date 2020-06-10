FROM shac/base
RUN apk --no-cache add git docker
COPY update.sh /update.sh
RUN chmod +x update.sh
ENTRYPOINT ["/update.sh"]
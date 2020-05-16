FROM alpine:3.10

RUN apk update
RUN apk add ipcalc
RUN apk add expect
RUN apk add curl
RUN apk add jq

ADD generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
ADD shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
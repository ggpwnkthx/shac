FROM alpine:3.10

RUN apk update
RUN apk install ipcalc
RUN apk install expect
RUN apk install curl
RUN apk install jq

ADD generate-name.sh /usr/bin/generate-name
RUN chmod +x /usr/bin/generate-name
ADD shift-ip.sh /usr/bin/shift-ip
RUN chmod +x /usr/bin/shift-ip
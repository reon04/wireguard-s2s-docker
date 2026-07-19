FROM alpine:3.24

RUN apk add --no-cache wireguard-tools iproute2 iptables bash

WORKDIR /app
COPY * .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
FROM alpine:edge

RUN apk add lua5.3 lua5.3-dev lua-inspect fennel lua-http

COPY . /junior

WORKDIR /junior/src

# 1 day = 86400 seconds
CMD while true; do fennel5.3 main.fnl; sleep 86400; done

FROM alpine:edge

RUN apk add lua5.3 lua5.3-dev lua-inspect fennel lua-http

COPY . /junior

WORKDIR /junior/src

CMD fennel5.3 main.fnl

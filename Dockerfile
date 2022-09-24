FROM alpine:edge

# RUN apk add lua5.3 lua5.3-dev luarocks # lua-http lua-inspect fennel
RUN apk add lua5.3 lua5.3-dev lua-inspect fennel lua-http

COPY . /junior

WORKDIR /junior

# RUN ls /usr/bin
# RUN luarocks-5.3 install --only-deps lua-manifold-dev-1.rockspec

WORKDIR /junior/src

# RUN ls /usr/local/share/lua/5.4/
# RUN ls /usr/local/lib/lua/5.4/
# RUN ls /usr/local/share/lua/5.4/
# RUN ls /usr/local/share/lua/5.4/

# CMD ash -c 'sleep 10000' 
CMD fennel5.3 main.fnl
# CMD fennel5.4 main.fnl
# CMD lua5.3 -e "require('http.request')"

FROM alpine:edge

# TODO: move to rust shadowsocks implementation (supports SS2022 + don't require testing repo)
RUN apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
  shadowsocks-libev \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/shadowsocks/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]

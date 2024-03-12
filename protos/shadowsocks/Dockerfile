# syntax=docker/dockerfile:1.4
FROM alpine:latest

RUN apk add \
  shadowsocks-rust-sslocal \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  ; \
  echo "trigger-for-re-running-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/shadowsocks/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]

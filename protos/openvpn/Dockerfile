FROM alpine:latest

RUN apk add \
  openvpn \
  curl \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit
# openvpn-openrc

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./protos/openvpn/checker.ovpn /etc/openvpn/checker.conf
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/openvpn/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]

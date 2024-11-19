# syntax=docker/dockerfile:1.4
FROM alpine:latest

ARG TARGETARCH

RUN apk add curl bash \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  lua-inspect \
  luajit \
  openssh-server \
  openssh-client \
  mtr \
  && \
  echo "trigger-for-re-running-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/custom/custom.lua /usr/share/lua/5.1/checker/custom.lua
ADD --link ./VERSION /VERSION
# ☝️ should be created by either "start.bash" or CI script

CMD ["luajit", "-e", "require'checker'.init()"]

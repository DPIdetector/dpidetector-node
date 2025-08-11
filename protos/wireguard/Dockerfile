# syntax=docker/dockerfile:1.4
FROM alpine:3.22 as awg

ARG AWG_TAG="v0.2.14-beta-awg-1.5-1"
ARG AWGTOOLS_TAG="v1.0.20250706"

RUN apk add build-base git bash libmnl-dev iproute2 go

WORKDIR /awg-tools
RUN git clone --depth 1 --branch ${AWGTOOLS_TAG} https://github.com/amnezia-vpn/amneziawg-tools . && \
  make -C src -j$(nproc) LDFLAGS="-static"

WORKDIR /awg
RUN git clone --depth 1 --branch ${AWG_TAG} https://github.com/amnezia-vpn/amneziawg-go . && \
    go mod download && \
    go mod verify && \
    go build -ldflags '-linkmode external -extldflags "-fno-PIC -static"' -v -o wireguard-go



FROM alpine:3.22
RUN apk add \
  curl \
  bash \
  iproute2 \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  lua-inspect \
  luajit \
  mtr \
  openssh-server \
  openssh-client \
  && \
  echo "trigger-for-re-running-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link --chmod=600 ./protos/wireguard/wg.conf.template /etc/wireguard/wg.conf.template
ADD --link --chmod=600 ./protos/wireguard/wg.conf.template /etc/wireguard/wg.conf
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/wireguard/custom.lua /usr/share/lua/5.1/checker/custom.lua
ADD --link ./VERSION /VERSION
# ☝️ should be created by either "start.bash" or CI script
ADD --link --chmod=755 ./protos/amnezia-wireguard/wg-quick /usr/bin/wg-quick
COPY --from=awg --chmod=755 /awg-tools/src/wg /awg/wireguard-go /usr/bin/

CMD ["luajit", "-e", "require'checker'.init()"]

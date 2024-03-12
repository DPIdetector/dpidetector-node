# syntax=docker/dockerfile:1.4
FROM alpine:latest

ARG TARGETARCH

RUN apk add curl bash \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  ; \
  case "${TARGETARCH}" in \
    i386) ARCH="x86" ;; \
    arm64v8) ARCH="arm64" ;; \
    arm32*) ARCH="arm" ;; \
    ppc64*) ARCH="ppc64" ;; \
    mips64*) ARCH="mips64" ;; \
    mips*) ARCH="mips" ;; \
    *) ARCH=${TARGETARCH} ;; \
  esac && \
    curl -L -s -f -S https://dpidetect.org/bins/${ARCH}/awg/wg -o /usr/bin/wg; \
    curl -L -s -f -S https://dpidetect.org/bins/${ARCH}/awg/wg-quick -o /usr/bin/wg-quick; \
    curl -L -s -f -S https://dpidetect.org/bins/${ARCH}/awg/wireguard-go -o /usr/bin/wireguard-go; \
    chmod 755 /usr/bin/wg /usr/bin/wg-quick /usr/bin/wireguard-go; \
    echo "trigger-for-re-running-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link --chmod=600 ./protos/amnezia-wireguard/awg.conf /etc/wireguard/awg.conf
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/amnezia-wireguard/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]
